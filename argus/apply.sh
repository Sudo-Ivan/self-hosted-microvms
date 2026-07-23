#!/bin/sh
# Apply or refresh the Argus central firewall policy.
#
# Usage:
#   sudo ./argus/apply.sh
#   sudo ./mvm argus apply

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=lib.sh
. "${REPO_ROOT}/argus/lib.sh"
load_config
ensure_root "$@"
argus_apply
