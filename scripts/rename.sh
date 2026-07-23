#!/bin/sh
# Rename a stopped instance. Keeps guest IP, MAC, and CID. Retargets TAP name and paths.
#
# Usage:
#   ./scripts/rename.sh <old> <new>
#   ./mvm rename navi music

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/guestfs.sh
. "${LIB_DIR}/guestfs.sh"
load_config

OLD="${1:-}"
NEW="${2:-}"
if [ -z "${OLD}" ] || [ -z "${NEW}" ]; then
	die "usage: $0 <old> <new>"
fi
validate_name "${OLD}"
validate_name "${NEW}"
[ "${OLD}" != "${NEW}" ] || die "old and new must differ"

OLD_DIR="$(instance_dir "${OLD}")"
NEW_DIR="$(instance_dir "${NEW}")"
[ -d "${OLD_DIR}" ] || die "instance not found: ${OLD}"
[ ! -e "${NEW_DIR}" ] || die "instance already exists: ${NEW}"

load_instance "${OLD}"
if is_running "${PID_FILE}"; then
	die "stop ${OLD} before renaming (./mvm stop ${OLD})"
fi

info "renaming ${OLD} -> ${NEW}"
mv "${OLD_DIR}" "${NEW_DIR}"

# Keep guest IP and CID. Retarget TAP name and absolute disk paths.
config_set_kv "${NEW_DIR}/config.env" INSTANCE_NAME "${NEW}"
config_set_kv "${NEW_DIR}/config.env" TAP_DEV "fc-${NEW}"
config_set_kv "${NEW_DIR}/config.env" ROOTFS_PATH "${NEW_DIR}/rootfs.ext4"
config_set_kv "${NEW_DIR}/config.env" DATA_PATH "${NEW_DIR}/data.ext4"

echo
echo "renamed ${OLD} -> ${NEW}"
echo "  guest ip:  ${GUEST_IP} (unchanged)"
echo "  tap:       fc-${NEW}"
echo "  start:     ./mvm start ${NEW}"
echo "  note:      Argus peer names and secrets vault keys use the new name"
echo "             update ALLOW_PEERS on peers and re-set secrets if needed"
