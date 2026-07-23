#!/bin/sh
# Show recent guest DNS queries (domains allowed or blocked).
#
# Usage:
#   ./argus/queries.sh
#   ./argus/queries.sh <name>
#   ./argus/queries.sh <name> 100

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=lib.sh
. "${REPO_ROOT}/argus/lib.sh"
load_config
argus_load_global_policy

FILTER_NAME=""
LINES="${ARGUS_DNS_QUERY_LINES}"

case "${1:-}" in
*[!0-9]*|'')
	if [ -n "${1:-}" ]; then
		FILTER_NAME="$1"
		case "${2:-}" in
		*[!0-9]*|'') ;;
		*) LINES="$2" ;;
		esac
	fi
	;;
*)
	LINES="$1"
	;;
esac

argus_dns_show_queries "${LINES}" "${FILTER_NAME}"
