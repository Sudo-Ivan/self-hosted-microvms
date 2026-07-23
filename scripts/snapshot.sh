#!/bin/sh
# Full VM snapshot (rootfs + data + config) for whole-instance rollback.
#
# Usage:
#   ./scripts/snapshot.sh <name> [label]
#   ./mvm snapshot navi before-upgrade

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/backup.sh
. "${LIB_DIR}/backup.sh"
load_config

NAME="${1:-}"
LABEL="${2:-snapshot}"
[ -n "${NAME}" ] || die "usage: $0 <name> [label]"

dest="$(backup_create "${NAME}" "${LABEL}" 1)"
backup_prune "${NAME}" "${BACKUP_KEEP}"
echo "snapshot ready: ${dest}"
echo "restore with: ./mvm restore ${NAME} $(basename "${dest}")"
