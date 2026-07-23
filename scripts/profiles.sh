#!/bin/sh
# List resource profiles.

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/profiles.sh
. "${LIB_DIR}/profiles.sh"
load_config

printf '%-12s %s\n' "PROFILE" "RESOURCES"
printf '%s\n' "------------------------------------------------------------"
list_profiles
