#!/bin/sh
# Resize an instance: memory, vCPU, and/or grow data/rootfs disks.
#
# Usage:
#   ./scripts/resize.sh <name> --mem 1024
#   ./scripts/resize.sh <name> --vcpu 2 --data-mib 8192 --restart
#   ./scripts/resize.sh <name> --rootfs-mib 4096

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/guestfs.sh
. "${LIB_DIR}/guestfs.sh"
load_config

NAME=""
NEW_MEM=""
NEW_VCPU=""
NEW_DATA=""
NEW_ROOTFS=""
RESTART=0

usage() {
	cat <<'EOF'
Usage:
  ./mvm resize <name> [--mem MiB] [--vcpu N] [--data-mib MiB] [--rootfs-mib MiB] [--restart]

Notes:
  - mem and vcpu apply on next boot (use --restart to bounce now)
  - data/rootfs only grow (never shrink) and require a stopped guest
  - Firecracker machine config is rebuilt on start from config.env
  - to copy an instance use ./mvm clone <src> <dst> (not shrink)
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--mem)
		NEW_MEM="$2"
		shift 2
		;;
	--vcpu|--cpu)
		NEW_VCPU="$2"
		shift 2
		;;
	--data-mib|--data)
		NEW_DATA="$2"
		shift 2
		;;
	--rootfs-mib|--rootfs)
		NEW_ROOTFS="$2"
		shift 2
		;;
	--restart)
		RESTART=1
		shift
		;;
	-h|--help)
		usage
		exit 0
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${NAME}" ]; then
			NAME="$1"
			shift
		else
			die "unexpected argument: $1"
		fi
		;;
	esac
done

[ -n "${NAME}" ] || {
	usage >&2
	exit 1
}
[ -n "${NEW_MEM}${NEW_VCPU}${NEW_DATA}${NEW_ROOTFS}" ] \
	|| die "pass at least one of --mem --vcpu --data-mib --rootfs-mib"

load_instance "${NAME}"
CFG="${INSTANCE_DIR}/config.env"
was_running=0
if is_running "${PID_FILE}"; then
	was_running=1
fi

if [ -n "${NEW_DATA}" ] || [ -n "${NEW_ROOTFS}" ]; then
	if [ "${was_running}" = "1" ]; then
		if [ "${RESTART}" = "1" ]; then
			info "stopping ${NAME} for disk resize"
			run_as_root "$(mvm_bin)" stop "${NAME}"
			was_running=0
			load_instance "${NAME}"
		else
			die "${NAME} is running. stop it or pass --restart before growing disks"
		fi
	fi
fi

changed=0

if [ -n "${NEW_MEM}" ]; then
	case "${NEW_MEM}" in
	*[!0-9]*|'') die "--mem must be integer MiB" ;;
	esac
	if [ "${NEW_MEM}" -lt 64 ]; then die "--mem too small"; fi
	config_set_kv "${CFG}" MEM_MIB "${NEW_MEM}"
	info "MEM_MIB -> ${NEW_MEM}"
fi

if [ -n "${NEW_VCPU}" ]; then
	case "${NEW_VCPU}" in
	*[!0-9]*|'') die "--vcpu must be integer" ;;
	esac
	if [ "${NEW_VCPU}" -lt 1 ] || [ "${NEW_VCPU}" -gt 32 ]; then die "--vcpu out of range"; fi
	config_set_kv "${CFG}" VCPU_COUNT "${NEW_VCPU}"
	info "VCPU_COUNT -> ${NEW_VCPU}"
fi

if [ -n "${NEW_DATA}" ]; then
	grow_ext4_image "${DATA_PATH}" "${NEW_DATA}"
	config_set_kv "${CFG}" DATA_SIZE_MIB "${NEW_DATA}"
fi

if [ -n "${NEW_ROOTFS}" ]; then
	grow_ext4_image "${ROOTFS_PATH}" "${NEW_ROOTFS}"
	config_set_kv "${CFG}" ROOTFS_SIZE_MIB "${NEW_ROOTFS}"
fi

load_instance "${NAME}"
echo
echo "resized ${NAME}"
echo "  memory:  ${MEM_MIB} MiB"
echo "  vcpu:    ${VCPU_COUNT}"
echo "  data:    $(image_size_mib "${DATA_PATH}") MiB"
echo "  rootfs:  $(image_size_mib "${ROOTFS_PATH}") MiB"

if [ "${RESTART}" = "1" ]; then
	if is_running "${PID_FILE}"; then
		info "restarting ${NAME} to apply machine config"
		run_as_root "$(mvm_bin)" restart "${NAME}"
	else
		info "starting ${NAME}"
		run_as_root "$(mvm_bin)" start "${NAME}"
	fi
elif [ -n "${NEW_MEM}" ] || [ -n "${NEW_VCPU}" ]; then
	if is_running "${PID_FILE}"; then
		echo "mem/vcpu changes apply after restart: $(root_helper) $(mvm_bin) restart ${NAME}"
	else
		echo "mem/vcpu changes apply on next start"
	fi
fi
