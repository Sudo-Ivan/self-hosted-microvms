#!/bin/sh
# Restart a microvm instance.
#
# Usage:
#   ./scripts/restart.sh <name>

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NAME="${1:-}"
[ -n "${NAME}" ] || { echo "usage: $0 <name>" >&2; exit 1; }

"${ROOT}/scripts/stop.sh" "${NAME}" || true
exec "${ROOT}/scripts/start.sh" "${NAME}"
