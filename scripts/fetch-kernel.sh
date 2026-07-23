#!/bin/sh
# Download a Firecracker CI guest kernel into shared/vmlinux.
#
# Usage:
#   ./scripts/fetch-kernel.sh
#   KERNEL_SERIES=6.1 ./scripts/fetch-kernel.sh

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config
ensure_shared
require_cmd curl

ARCH="$(uname -m)"
case "${ARCH}" in
x86_64 | aarch64) ;;
arm64) ARCH=aarch64 ;;
*)
	die "unsupported arch: ${ARCH}"
	;;
esac

S3="https://s3.amazonaws.com/spec.ccfc.min"
KERNEL_SERIES="${KERNEL_SERIES:-6.1}"

info "listing Firecracker CI artifact prefixes"
PREFIXES_XML="$(curl -fsSL "${S3}?list-type=2&prefix=firecracker-ci/&delimiter=/")"
CI_PREFIX="$(printf '%s\n' "${PREFIXES_XML}" \
	| grep -oE 'firecracker-ci/[0-9]{8}-[^/<]+/' \
	| sort \
	| tail -n1 || true)"

[ -n "${CI_PREFIX}" ] || die "no dated firecracker-ci prefixes found"

info "using prefix ${CI_PREFIX}${ARCH}/"
KEYS_XML="$(curl -fsSL "${S3}?list-type=2&prefix=${CI_PREFIX}${ARCH}/vmlinux-")"
_fk_keys=$(mktemp)
printf '%s\n' "${KEYS_XML}" \
	| grep -oE "${CI_PREFIX}${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]+" \
	| sort -V \
	| uniq >"${_fk_keys}"

[ -s "${_fk_keys}" ] || die "no vmlinux keys under ${CI_PREFIX}${ARCH}/"

LATEST_KEY=""
key=
base=
while read -r key; do
	[ -n "${key}" ] || continue
	base="$(basename "${key}")"
	case "${base}" in
	vmlinux-${KERNEL_SERIES}.*)
		LATEST_KEY="${key}"
		;;
	esac
done <"${_fk_keys}"
if [ -z "${LATEST_KEY}" ]; then
	LATEST_KEY="$(tail -n 1 "${_fk_keys}")"
	echo "no vmlinux-${KERNEL_SERIES}.* found falling back to ${LATEST_KEY}"
fi
rm -f "${_fk_keys}"

DEST="${KERNEL_PATH}"
TMP="${DEST}.partial"

info "downloading ${S3}/${LATEST_KEY}"
curl -fL --progress-bar -o "${TMP}" "${S3}/${LATEST_KEY}"
mv -f "${TMP}" "${DEST}"
chmod a-w "${DEST}" || true

printf '%s\n' "${LATEST_KEY}" >"${SHARED_DIR}/vmlinux.source"
echo "wrote ${DEST}"
ls -lh "${DEST}"
