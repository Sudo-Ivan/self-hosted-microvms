#!/bin/sh
# Fetch remote DNS blocklists, compile, and reload dnsmasq.
#
# Usage:
#   sudo ./argus/dns-update.sh
#   sudo ./mvm argus dns-update

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=lib.sh
. "${REPO_ROOT}/argus/lib.sh"
load_config
argus_load_global_policy
argus_dns_update
