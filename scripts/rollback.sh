#!/bin/sh
# Roll back an instance to its latest pre-update or manual backup.
#
# Usage:
#   ./scripts/rollback.sh <name>
#   ./scripts/rollback.sh <name> <stamp>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/backup.sh
. "${LIB_DIR}/backup.sh"
load_config

NAME="${1:-}"
STAMP="${2:-latest}"
[ -n "${NAME}" ] || die "usage: $0 <name> [stamp]"

info "rolling back ${NAME}"
backup_restore "${NAME}" "${STAMP}"
info "rollback complete"
