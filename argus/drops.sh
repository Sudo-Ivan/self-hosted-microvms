#!/bin/sh
# Show recent Argus drop events from the kernel log.
#
# Usage:
#   sudo ./argus/drops.sh
#   sudo ./argus/drops.sh 100

set -eu

LINES="${1:-50}"

if [ "$(id -u)" -ne 0 ]; then
	echo "drops needs root to read kernel logs" >&2
	exit 1
fi

if command -v journalctl >/dev/null 2>&1; then
	journalctl -k -n "${LINES}" --no-pager 2>/dev/null | grep -E 'argus-drop' || echo "(no recent argus drops)"
	exit 0
fi

dmesg -T | grep -E 'argus-drop' | tail -n "${LINES}" || echo "(no recent argus drops)"
