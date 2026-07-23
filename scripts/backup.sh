#!/bin/sh
# Backup instance data disk and config (optionally rootfs with --full).
#
# Usage:
#   ./scripts/backup.sh <name> [label]
#   ./scripts/backup.sh <name> --full [label]
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

NAME=""
LABEL="manual"
FULL=0

while [ $# -gt 0 ]; do
	case "$1" in
	--full)
		FULL=1
		shift
		;;
	-h|--help)
		sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${NAME}" ]; then
			NAME="$1"
		else
			LABEL="$1"
		fi
		shift
		;;
	esac
done

[ -n "${NAME}" ] || die "usage: $0 <name> [label] | <name> --full [label] | --list [name]"

dest="$(backup_create "${NAME}" "${LABEL}" "${FULL}")"
backup_prune "${NAME}" "${BACKUP_KEEP}"
echo "backup ready: ${dest}"
