#!/bin/sh
# One-shot prepare shared kernel and base rootfs.
#
# Usage:
#   ./scripts/setup.sh
#   ./scripts/setup.sh --rebuild
#   ./scripts/setup.sh --host
#   ./scripts/setup.sh --check

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config
ensure_shared

REBUILD=0
HOST_PREP=0
CHECK_ONLY=0
for arg in "$@"; do
	case "${arg}" in
	--rebuild) REBUILD=1 ;;
	--host) HOST_PREP=1 ;;
	--check) CHECK_ONLY=1 ;;
	-h | --help)
		cat <<'EOF'
Usage:
  ./mvm setup              fetch kernel and build base rootfs
  ./mvm setup --rebuild    force kernel and base rebuild
  ./mvm setup --host       setup plus doctor and config.env
  ./mvm setup --check      doctor only (fast preflight)
EOF
		exit 0
		;;
	*)
		die "unknown argument: ${arg}"
		;;
	esac
done

if [ "${CHECK_ONLY}" = "1" ]; then
	exec "${SCRIPTS_DIR}/doctor.sh"
fi

if [ "${HOST_PREP}" = "1" ]; then
	if [ ! -f config.env ] && [ -f config.example.env ]; then
		cp -f config.example.env config.env
		info "wrote config.env"
	fi
fi

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

if [ "${HOST_PREP}" = "1" ]; then
	info "host preflight"
	"${SCRIPTS_DIR}/doctor.sh"
fi

echo
echo "setup complete"
echo "  kernel: ${KERNEL_PATH}"
echo "  base:   ${BASE_ROOTFS_PATH}"
echo "  argus:  ${ARGUS_DIR}/policy.env"
echo
echo "run a service:"
echo "  ./mvm templates"
echo "  ./mvm info alpine-shell"
echo "  ./mvm run alpine-shell"
if [ "${HOST_PREP}" = "1" ]; then
	echo
	echo "passwordless start/stop (optional):"
	echo "  doas ./mvm doas install"
	echo "  sudo ./mvm sudoers install"
fi
echo "apply firewall and dns:"
echo "  sudo ./mvm argus apply"
