#!/bin/sh
# Destroy an instance and its disks.
#
# Usage:
#   ./scripts/destroy.sh <name>
#   ./scripts/destroy.sh <name> --yes

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME="${1:-}"
YES="${2:-}"
[ -n "${NAME}" ] || die "usage: $0 <name> [--yes]"
validate_name "${NAME}"

DIR="$(instance_dir "${NAME}")"
[ -d "${DIR}" ] || die "instance not found: ${NAME}"

# Elevate early so confirmation + Argus cleanup run as root once.
ensure_root "$@"

if [ "${YES}" != "--yes" ]; then
	echo "This deletes ${DIR} including rootfs and data volumes."
	printf "Type the instance name to confirm: "
	read -r answer
	[ "${answer}" = "${NAME}" ] || die "aborted"
fi

"${SCRIPTS_DIR}/stop.sh" "${NAME}" >/dev/null 2>&1 || true
rm -rf "${DIR}"

# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=../argus/lib.sh
. "${REPO_ROOT}/argus/lib.sh"
argus_load_global_policy
if [ "${ARGUS_ENABLED}" = "1" ] && command -v nft >/dev/null 2>&1; then
	argus_apply >/dev/null || true
fi

echo "destroyed ${NAME}"
