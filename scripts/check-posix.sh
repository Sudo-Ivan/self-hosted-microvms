#!/bin/sh
# Syntax and POSIX shellcheck for host, guest, and template scripts.
#
# Usage:
#   ./scripts/check-posix.sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${ROOT}"

fail=0

check_syntax() {
	_cs_file=$1
	if command -v dash >/dev/null 2>&1; then
		dash -n "${_cs_file}" || fail=1
	else
		# bash --posix is a stand-in when dash is not installed
		bash --posix -n "${_cs_file}" || fail=1
	fi
}

echo "==> syntax (dash -n or bash --posix -n)"
check_syntax mvm
for f in scripts/*.sh lib/*.sh argus/*.sh guest/*.sh templates/_common/*.sh templates/*/*.sh; do
	[ -f "${f}" ] || continue
	check_syntax "${f}"
done

if ! command -v shellcheck >/dev/null 2>&1; then
	echo "error: shellcheck not found on PATH" >&2
	exit 1
fi

echo "==> shellcheck -s sh (host)"
shellcheck -s sh -x \
	-e SC1090,SC1091,SC2034,SC2086,SC2046,SC2016,SC1007,SC2269 \
	mvm scripts/*.sh lib/*.sh argus/*.sh || fail=1

echo "==> shellcheck -s sh (guest + templates)"
shellcheck -s sh guest/*.sh templates/_common/*.sh templates/*/*.sh || fail=1

if [ "${fail}" -ne 0 ]; then
	echo "check-posix: FAILED" >&2
	exit 1
fi
echo "check-posix: OK"
