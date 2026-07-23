#!/bin/sh
# Follow guest connections and Argus drop log lines.
#
# Usage:
#   sudo ./argus/watch.sh
#   sudo ./argus/watch.sh <name>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=lib.sh
. "${REPO_ROOT}/argus/lib.sh"
load_config

FILTER_NAME="${1:-}"

echo "watching guest flows and argus-drop* kernel messages"
echo "filter: ${FILTER_NAME:-all}"
echo "ctrl-c to stop"
echo

# Periodic connection snapshot plus kernel drop logs.
(
	while true; do
		echo "---- $(date -Is) connections ----"
		if [ -n "${FILTER_NAME}" ]; then
			"${ARGUS_DIR}/status.sh" "${FILTER_NAME}" | sed -n '/^Active connections/,/^$/p'
		else
			"${ARGUS_DIR}/status.sh" | sed -n '/^Active connections/,/^$/p'
		fi
		sleep 5
	done
) &
snap_pid=$!

cleanup() {
	kill "${snap_pid}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

if [ "$(id -u)" -eq 0 ] && command -v dmesg >/dev/null 2>&1; then
	dmesg -wT 2>/dev/null | grep --line-buffered -E 'argus-drop' || true
else
	echo "(run as root to stream argus-drop kernel messages)"
	wait "${snap_pid}"
fi
