#!/bin/sh
# Backup instance data disk and config.
#
# Usage:
#   ./scripts/backup.sh <name> [label]
#   ./scripts/backup.sh --list [name]

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/backup.sh
. "${LIB_DIR}/backup.sh"
load_config

if [ "${1:-}" = "--list" ] || [ "${1:-}" = "list" ]; then
	backup_list "${2:-}"
	exit 0
fi

NAME="${1:-}"
LABEL="${2:-manual}"
[ -n "${NAME}" ] || die "usage: $0 <name> [label] | --list [name]"

dest="$(backup_create "${NAME}" "${LABEL}")"
backup_prune "${NAME}" "${BACKUP_KEEP}"
echo "backup ready: ${dest}"
