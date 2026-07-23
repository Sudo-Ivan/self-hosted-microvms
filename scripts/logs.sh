#!/bin/sh
# Follow serial console output for an instance.
#
# Usage:
#   ./scripts/logs.sh <name>
#   ./scripts/logs.sh <name> --boot

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME="${1:-}"
[ -n "${NAME}" ] || die "usage: $0 <name> [--boot]"
load_instance "${NAME}"

TARGET="${STDOUT_PATH}"
if [ "${2:-}" = "--boot" ]; then
	TARGET="${LOG_PATH}"
fi

[ -f "${TARGET}" ] || die "log not found: ${TARGET}"
exec tail -n 100 -F "${TARGET}"
