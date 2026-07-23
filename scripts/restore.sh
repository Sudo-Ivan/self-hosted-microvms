#!/bin/sh
# Restore instance data from a backup stamp or latest.
#
# Usage:
#   ./scripts/restore.sh <name> [stamp|latest]

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/backup.sh
. "${LIB_DIR}/backup.sh"
load_config

NAME="${1:-}"
STAMP="${2:-latest}"
[ -n "${NAME}" ] || die "usage: $0 <name> [stamp|latest]"

backup_restore "${NAME}" "${STAMP}"
