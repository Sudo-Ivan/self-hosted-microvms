#!/bin/sh
# Prompt for template secret keys and store them in the host vault.
#
# Usage:
#   ./scripts/secrets-wizard.sh <instance>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

INSTANCE="${1:-}"
[ -n "${INSTANCE}" ] || die "usage: ./mvm secrets wizard <instance>"

load_instance "${INSTANCE}"
_tpl="${TEMPLATE:-}"
[ -n "${_tpl}" ] || die "instance ${INSTANCE} has no TEMPLATE in config.env"

load_template "${_tpl}"

_keys="${TEMPLATE_SECRETS_KEYS}"
if [ -z "${_keys}" ]; then
	_keys="$(grep -oE '\$\{[A-Z0-9_]+\:\?' "${TEMPLATE_DIR}/run.sh" 2>/dev/null \
		| sed 's/\${\([^:?]*\).*/\1/' \
		| sort -u \
		| tr '\n' ',' \
		| sed 's/,$//')" || true
fi

if [ -z "${_keys}" ]; then
	echo "no secret keys defined for template ${_tpl}"
	echo "set keys manually: ./mvm secrets set ${INSTANCE} KEY=value"
	exit 0
fi

if ! mvmsec_resolve >/dev/null 2>&1; then
	die "mvmsec not found. build with: ./scripts/build-mvmsec.sh"
fi

if [ ! -f "${SECRETS_DIR}/protect.json" ] && [ ! -f "${SECRETS_DIR}/vault.json.age" ]; then
	echo "secrets vault not initialized"
	echo "run: ./mvm secrets init"
	"${SCRIPTS_DIR}/secrets.sh" init
fi

_existing=""
if "${SCRIPTS_DIR}/secrets.sh" exists "${INSTANCE}" 2>/dev/null; then
	_existing="$("${SCRIPTS_DIR}/secrets.sh" list "${INSTANCE}" 2>/dev/null || true)"
fi

_to_set=""
_sk_old_ifs=${IFS}
IFS=,
for _key in ${_keys}; do
	IFS=${_sk_old_ifs}
	_key="$(echo "${_key}" | tr -d '[:space:]')"
	[ -n "${_key}" ] || continue
	if echo "${_existing}" | grep -qx "${_key}" 2>/dev/null; then
		echo "skip ${INSTANCE} ${_key} (already set)"
		continue
	fi
	printf 'value for %s: ' "${_key}" >&2
	_sensitive=0
	case "${_key}" in
	*PASSWORD* | *SECRET* | *TOKEN* | *KEY*)
		_sensitive=1
		;;
	esac
	if [ "${_sensitive}" = "1" ]; then
		stty -echo 2>/dev/null || true
	fi
	read -r _val
	if [ "${_sensitive}" = "1" ]; then
		stty echo 2>/dev/null || true
		printf '\n' >&2
	fi
	[ -n "${_val}" ] || die "empty value for ${_key}"
	if [ -n "${_to_set}" ]; then
		_to_set="${_to_set} ${_key}=${_val}"
	else
		_to_set="${_key}=${_val}"
	fi
	IFS=,
done
IFS=${_sk_old_ifs}

if [ -z "${_to_set}" ]; then
	echo "no new secrets to set"
	exit 0
fi

# shellcheck disable=SC2086
"${SCRIPTS_DIR}/secrets.sh" set "${INSTANCE}" ${_to_set}

dir="$(instance_dir "${INSTANCE}")"
if is_running "${dir}/firecracker.pid" 2>/dev/null; then
	echo "restart to load secrets: ./mvm restart ${INSTANCE}"
fi
