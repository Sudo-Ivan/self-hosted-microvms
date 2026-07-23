#!/bin/sh
# Stop a microvm instance.
#
# Usage:
#   ./scripts/stop.sh <name>
#   ./scripts/stop.sh --all

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
load_config

stop_one() {
	name="$1"
	load_instance "${name}"

	if [ -S "${API_SOCK}" ]; then
		curl --unix-socket "${API_SOCK}" -s -X PUT "http://localhost/actions" \
			-H "Content-Type: application/json" \
			-d '{"action_type": "SendCtrlAltDel"}' >/dev/null 2>&1 || true
		sleep 1 || true
	fi

	if [ -f "${PID_FILE}" ]; then
		pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
		if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
			kill "${pid}" 2>/dev/null || true
			for _ in 1 2 3 4 5 6 7 8 9 10; do
				kill -0 "${pid}" 2>/dev/null || break
				sleep 1
			done
			kill -9 "${pid}" 2>/dev/null || true
		fi
		rm -f "${PID_FILE}"
	fi

	if [ "${KEEP_TAP:-0}" != "1" ]; then
		teardown_tap "${TAP_DEV}"
	fi

	# shellcheck source=../lib/shares.sh
	. "${LIB_DIR}/shares.sh"
	shares_remove_host_exports

	# shellcheck source=../argus/lib.sh
	. "${REPO_ROOT}/argus/lib.sh"
	argus_load_global_policy
	if [ "${ARGUS_ENABLED}" = "1" ] && [ "$(id -u)" -eq 0 ] && command -v nft >/dev/null 2>&1; then
		argus_apply >/dev/null
	else
		remove_port_forwards "${GUEST_IP}" "${PORT_FORWARDS}"
	fi

	rm -f "${API_SOCK}" "${VSOCK_UDS}" "${VSOCK_UDS}_"* 2>/dev/null || true
	echo "stopped ${name}"
}

if [ "${1:-}" = "--all" ]; then
	for dir in "${INSTANCES_DIR}"/*/; do
		name="$(basename "${dir}")"
		[ -f "${dir}/config.env" ] || continue
		stop_one "${name}" || true
	done
	exit 0
fi

NAME="${1:-}"
[ -n "${NAME}" ] || die "usage: $0 <name>|--all"
stop_one "${NAME}"
