#!/bin/sh
# Fetch host-injected secrets from Firecracker MMDS V2 into /run/secrets/env.
# Safe to call when no secrets are present. Retries briefly for host inject race.

set -eu

MMDS_IP="${MMDS_IP:-169.254.169.254}"
MMDS_BASE="http://${MMDS_IP}"
OUT_DIR="/run/secrets"
OUT_FILE="${OUT_DIR}/env"
MAX_TRIES="${SECRETS_FETCH_TRIES:-30}"

if ! command -v curl >/dev/null 2>&1; then
	echo "fetch-secrets: curl missing skip MMDS" >&2
	exit 0
fi

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

mmds_token() {
	curl -fsS -X PUT \
		-H "X-metadata-token-ttl-seconds: 120" \
		"${MMDS_BASE}/latest/api/token"
}

mmds_get() {
	_path="$1"
	_tok="$2"
	curl -fsS \
		-H "X-metadata-token: ${_tok}" \
		"${MMDS_BASE}${_path}"
}

shell_escape() {
	# Wrap value in single quotes for sourcing.
	printf "'"
	printf '%s' "$1" | sed "s/'/'\\\\''/g"
	printf "'"
}

try=0
token=
keys=
while [ "${try}" -lt "${MAX_TRIES}" ]; do
	try=$((try + 1))
	if token="$(mmds_token 2>/dev/null)"; then
		if keys="$(mmds_get /latest/secrets "${token}" 2>/dev/null)"; then
			break
		fi
	fi
	token=
	keys=
	sleep 1
done

if [ -z "${token}" ] || [ -z "${keys}" ]; then
	echo "fetch-secrets: no MMDS secrets (optional)"
	exit 0
fi

tmp="${OUT_FILE}.tmp"
: >"${tmp}"
chmod 600 "${tmp}"

# MMDS returns one key name per line for dictionary nodes.
old_ifs=${IFS}
IFS='
'
set -f
# shellcheck disable=SC2086
set -- ${keys}
set +f
IFS=${old_ifs}

for key in "$@"; do
	[ -n "${key}" ] || continue
	case "${key}" in
	*[!A-Za-z0-9_]* | [0-9]*)
		echo "fetch-secrets: skip invalid key" >&2
		continue
		;;
	esac
	val=
	if ! val="$(mmds_get "/latest/secrets/${key}" "${token}")"; then
		echo "fetch-secrets: failed to read key" >&2
		rm -f "${tmp}"
		exit 1
	fi
	{
		printf '%s=' "${key}"
		shell_escape "${val}"
		printf '\n'
	} >>"${tmp}"
done

mv -f "${tmp}" "${OUT_FILE}"
chmod 600 "${OUT_FILE}"
echo "fetch-secrets: wrote ${OUT_FILE}"
