#!/bin/sh
# Build a shared Alpine-based ext4 rootfs used as the template clone source.
#
# Usage:
#   ./scripts/build-base.sh
#   BASE_ROOTFS_SIZE_MIB=2048 ./scripts/build-base.sh

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config
ensure_shared
require_cmd curl
require_cmd tar
require_cmd truncate
require_cmd mkfs.ext4

ARCH="$(uname -m)"
case "${ARCH}" in
x86_64)
	ALPINE_ARCH=x86_64
	;;
aarch64 | arm64)
	ALPINE_ARCH=aarch64
	;;
*)
	die "unsupported arch: ${ARCH}"
	;;
esac

STAGING="${SHARED_DIR}/base-staging"
ROOTFS_IMG="${BASE_ROOTFS_PATH}"
SIZE_MIB="${BASE_ROOTFS_SIZE_MIB}"
# ALPINE_VERSION is the branch (for example 3.21). ALPINE_RELEASE is the full release tag.
ALPINE_VERSION="${ALPINE_VERSION}"
ALPINE_RELEASE="${ALPINE_RELEASE:-${ALPINE_VERSION}.3}"
TARBALL="${SHARED_DIR}/alpine-minirootfs-${ALPINE_RELEASE}-${ALPINE_ARCH}.tar.gz"
ALPINE_URL="${ALPINE_MINIROOTFS_URL:-https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_RELEASE}-${ALPINE_ARCH}.tar.gz}"

info "preparing base rootfs staging"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"

if [ ! -f "${TARBALL}" ]; then
	info "downloading Alpine minirootfs"
	curl -fL --progress-bar -o "${TARBALL}.partial" "${ALPINE_URL}"
	mv -f "${TARBALL}.partial" "${TARBALL}"
fi

info "extracting ${TARBALL}"
tar -xzf "${TARBALL}" -C "${STAGING}"

mkdir -p \
	"${STAGING}/data" \
	"${STAGING}/etc/microvm" \
	"${STAGING}/var/lib/microvm" \
	"${STAGING}/opt/service"

cp -f "${GUEST_DIR}/init" "${STAGING}/init"
cp -f "${GUEST_DIR}/first-boot.sh" "${STAGING}/etc/microvm/first-boot.sh"
cp -f "${GUEST_DIR}/run-service.sh" "${STAGING}/etc/microvm/run-service.sh"
cp -f "${GUEST_DIR}/update-guest.sh" "${STAGING}/etc/microvm/update-guest.sh"
cp -f "${GUEST_DIR}/mount-shares.sh" "${STAGING}/etc/microvm/mount-shares.sh"
cp -f "${GUEST_DIR}/fetch-secrets.sh" "${STAGING}/etc/microvm/fetch-secrets.sh"
cp -f "${GUEST_DIR}/prepare-harden.sh" "${STAGING}/etc/microvm/prepare-harden.sh"
cp -f "${GUEST_DIR}/harden-exec.sh" "${STAGING}/etc/microvm/harden-exec.sh"
chmod 755 \
	"${STAGING}/init" \
	"${STAGING}/etc/microvm/first-boot.sh" \
	"${STAGING}/etc/microvm/run-service.sh" \
	"${STAGING}/etc/microvm/update-guest.sh" \
	"${STAGING}/etc/microvm/mount-shares.sh" \
	"${STAGING}/etc/microvm/fetch-secrets.sh" \
	"${STAGING}/etc/microvm/prepare-harden.sh" \
	"${STAGING}/etc/microvm/harden-exec.sh"

# Default net file is replaced per instance at create time.
cp -f "${GUEST_DIR}/microvm-net.example" "${STAGING}/etc/microvm-net"

cat >"${STAGING}/etc/os-release" <<EOF
NAME="MicroVM Guest"
ID=microvm-guest
VERSION_ID=${ALPINE_VERSION}
PRETTY_NAME="MicroVM Guest (Alpine ${ALPINE_VERSION})"
EOF

# Enable community repo for more packages.
if [ -f "${STAGING}/etc/apk/repositories" ]; then
	cat >"${STAGING}/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community
EOF
fi

# Mark base as not yet provisioned for a service.
rm -f "${STAGING}/var/lib/microvm/provisioned"
printf 'base\n' >"${STAGING}/etc/microvm/template"

info "creating ext4 image (${SIZE_MIB} MiB)"
rm -f "${ROOTFS_IMG}"
truncate -s "${SIZE_MIB}M" "${ROOTFS_IMG}"
mkfs.ext4 -q -F -d "${STAGING}" -L microvm-base "${ROOTFS_IMG}"

echo "wrote ${ROOTFS_IMG}"
ls -lh "${ROOTFS_IMG}"
echo "staging left at ${STAGING} (safe to delete)"
