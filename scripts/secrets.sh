#!/bin/sh
# Host secrets vault wrapper around mvmsec.
#
# Usage:
#   ./scripts/secrets.sh init [--force]
#   ./scripts/secrets.sh set <instance> KEY=VALUE...
#   ./scripts/secrets.sh unset <instance> KEY
#   ./scripts/secrets.sh list [instance]
#   ./scripts/secrets.sh exists <instance>
#   ./scripts/secrets.sh export-mmds <instance>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

mvmsec_bin="$(mvmsec_resolve)" || {
	echo "error: mvmsec not found. build with: ./scripts/build-mvmsec.sh" >&2
	exit 1
}

export MVM_SHARED_DIR="${SHARED_DIR}"
exec "${mvmsec_bin}" "$@" --shared-dir "${SHARED_DIR}"
