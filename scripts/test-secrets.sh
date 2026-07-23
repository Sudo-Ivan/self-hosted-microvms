#!/bin/sh
# Smoke test the host secrets vault without Firecracker.
#
# Usage:
#   ./scripts/test-secrets.sh

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"

TMP=
cleanup() {
	if [ -n "${TMP}" ] && [ -d "${TMP}" ]; then
		rm -rf "${TMP}"
	fi
}
trap cleanup EXIT

if [ ! -x "${REPO_ROOT}/.tools/mvmsec" ]; then
	"${SCRIPTS_DIR}/build-mvmsec.sh"
fi
BIN="${REPO_ROOT}/.tools/mvmsec"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mvm-secrets-smoke.XXXXXX")"

"${BIN}" init --shared-dir "${TMP}" --no-tpm
"${BIN}" set alpha A_KEY=alpha-val --shared-dir "${TMP}"
"${BIN}" set beta B_KEY=beta-val --shared-dir "${TMP}"

out="$("${BIN}" list --shared-dir "${TMP}")"
echo "${out}" | grep -q '^alpha (1 keys)$' || {
	echo "FAIL list alpha" >&2
	exit 1
}
echo "${out}" | grep -q '^beta (1 keys)$' || {
	echo "FAIL list beta" >&2
	exit 1
}

exp="$("${BIN}" export-mmds alpha --shared-dir "${TMP}")"
echo "${exp}" | grep -q 'A_KEY' || {
	echo "FAIL export missing A_KEY" >&2
	exit 1
}
echo "${exp}" | grep -q 'alpha-val' || {
	echo "FAIL export missing value" >&2
	exit 1
}
echo "${exp}" | grep -q 'B_KEY' && {
	echo "FAIL export leaked B_KEY" >&2
	exit 1
}
echo "${exp}" | grep -q 'beta-val' && {
	echo "FAIL export leaked beta value" >&2
	exit 1
}

"${BIN}" exists alpha --shared-dir "${TMP}"
if "${BIN}" exists missing --shared-dir "${TMP}"; then
	echo "FAIL exists missing should fail" >&2
	exit 1
fi

"${BIN}" unset alpha A_KEY --shared-dir "${TMP}"
if "${BIN}" exists alpha --shared-dir "${TMP}"; then
	echo "FAIL exists after unset" >&2
	exit 1
fi

# Passphrase-wrapped identity
TMP2="$(mktemp -d "${TMPDIR:-/tmp}/mvm-secrets-pw.XXXXXX")"
export MVM_SECRETS_PASSPHRASE='smoke-passphrase'
"${BIN}" init --shared-dir "${TMP2}" --no-tpm --passphrase --force
"${BIN}" set demo S=1 --shared-dir "${TMP2}"
prot="$("${BIN}" protect status --shared-dir "${TMP2}")"
echo "${prot}" | grep -q 'mode=passphrase' || {
	echo "FAIL protect status mode" >&2
	exit 1
}
"${BIN}" exists demo --shared-dir "${TMP2}"
unset MVM_SECRETS_PASSPHRASE
rm -rf "${TMP2}"

echo "ok secrets smoke"