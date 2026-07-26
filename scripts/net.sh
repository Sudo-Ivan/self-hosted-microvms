#!/bin/sh
# Prepare host networking for NETWORK_MODE=user (root, one-time per instance).
#
# Usage:
#   sudo ./scripts/net.sh prepare [--host] [<instance>|--all]

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
load_config

ensure_root "$@"

DO_HOST=0
TARGET=""
for arg in "$@"; do
	case "${arg}" in
	--host)
		DO_HOST=1
		;;
	--all)
		TARGET="--all"
		;;
	-h | --help)
		cat <<'EOF'
Usage:
  sudo ./mvm net prepare [--host] [<instance>]
  sudo ./mvm net prepare --all

NETWORK_MODE=user lets ./mvm start and ./mvm stop run without root when taps
are pre-created for your user. This command needs root once per instance.

  --host   ensure bridge, forwarding, and Argus or masquerade only
  --all    prepare taps for every instance under instances/
EOF
		exit 0
		;;
	-*)
		die "unknown option: ${arg}"
		;;
	*)
		if [ -n "${TARGET}" ] && [ "${TARGET}" != "--all" ]; then
			die "unexpected argument: ${arg}"
		fi
		TARGET="${arg}"
		;;
	esac
done

if ! mvm_net_mode_user; then
	echo "note: NETWORK_MODE is ${NETWORK_MODE:-bridge} (set NETWORK_MODE=user in config.env for user taps)" >&2
fi

_net_user="$(net_resolve_user)"
[ -n "${_net_user}" ] || die "could not resolve NET_USER"
id "${_net_user}" >/dev/null 2>&1 || die "user not found: ${_net_user}"

prepare_host() {
	info "bridge and forwarding on ${BRIDGE_NAME}"
	setup_bridge
	enable_masquerade
	# shellcheck source=../argus/lib.sh
	. "${REPO_ROOT}/argus/lib.sh"
	argus_load_global_policy
	if [ "${ARGUS_ENABLED}" = "1" ]; then
		info "applying Argus"
		argus_apply
	fi
}

prepare_instance() {
	name="$1"
	load_instance "${name}"
	info "tap ${TAP_DEV} for user ${_net_user} (guest ${GUEST_IP})"
	prepare_tap_for_user "${TAP_DEV}" "${_net_user}" "${NET_GROUP:-}"
	if [ "${ARGUS_ENABLED}" != "1" ]; then
		apply_port_forwards "${GUEST_IP}" "${PORT_FORWARDS}"
	fi
}

if [ "${DO_HOST}" = "1" ] && [ -z "${TARGET}" ]; then
	prepare_host
	echo "host network ready for NETWORK_MODE=user"
	exit 0
fi

if [ "${DO_HOST}" = "1" ]; then
	prepare_host
fi

if [ -z "${TARGET}" ]; then
	die "usage: sudo ./mvm net prepare [--host] <instance>|--all"
fi

if [ "${TARGET}" = "--all" ]; then
	for dir in "${INSTANCES_DIR}"/*/; do
		[ -d "${dir}" ] || continue
		name="$(basename "${dir}")"
		[ -f "${dir}/config.env" ] || continue
		prepare_instance "${name}"
	done
else
	prepare_instance "${TARGET}"
fi

if [ "${DO_HOST}" != "1" ] && [ "${ARGUS_ENABLED}" = "1" ]; then
	# shellcheck source=../argus/lib.sh
	. "${REPO_ROOT}/argus/lib.sh"
	argus_load_global_policy
	info "refreshing Argus after tap changes"
	argus_apply
fi

echo "net prepare complete for user ${_net_user}"
