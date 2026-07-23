#!/bin/sh
# One-shot prepare shared kernel and base rootfs.
#
# Usage:
#   ./scripts/setup.sh
#   ./scripts/setup.sh --rebuild

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config
ensure_shared

REBUILD=0
for arg in "$@"; do
	case "${arg}" in
	--rebuild) REBUILD=1 ;;
	-h | --help)
		sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		die "unknown argument: ${arg}"
		;;
	esac
done

require_cmd firecracker
[ -r /dev/kvm ] || die "/dev/kvm is not readable"

if [ ! -f "${ARGUS_DIR}/policy.env" ] && [ -f "${ARGUS_DIR}/policy.example.env" ]; then
	cp -f "${ARGUS_DIR}/policy.example.env" "${ARGUS_DIR}/policy.env"
	info "wrote ${ARGUS_DIR}/policy.env"
fi

if [ "${REBUILD}" = "1" ] || [ ! -f "${KERNEL_PATH}" ]; then
	info "fetching guest kernel"
	"${SCRIPTS_DIR}/fetch-kernel.sh"
fi

if [ "${REBUILD}" = "1" ] || [ ! -d "${SHARED_DIR}/base-staging" ] || [ ! -f "${BASE_ROOTFS_PATH}" ]; then
	info "building base rootfs"
	"${SCRIPTS_DIR}/build-base.sh"
fi

echo
echo "setup complete"
echo "  kernel: ${KERNEL_PATH}"
echo "  base:   ${BASE_ROOTFS_PATH}"
echo "  argus:  ${ARGUS_DIR}/policy.env"
echo
echo "create an instance:"
echo "  ./scripts/create.sh <name> <template>"
echo "  ./scripts/templates.sh"
echo "apply firewall and dns:"
echo "  sudo ./mvm argus apply"
