#!/bin/sh
# Restart unhealthy guests.
#
# Usage:
#   ./scripts/watchdog.sh
#   ./scripts/watchdog.sh --once
#   ./scripts/watchdog.sh navi
#   WATCHDOG_INTERVAL=30 WATCHDOG_FAILURES=3 ./scripts/watchdog.sh

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

ONCE=0
FILTER=""
for arg in "$@"; do
	case "${arg}" in
	--once) ONCE=1 ;;
	-h|--help)
		sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		die "unknown flag: ${arg}"
		;;
	*)
		FILTER="${arg}"
		;;
	esac
done

STATE_DIR="${SHARED_DIR}/watchdog"
mkdir -p "${STATE_DIR}"

fail_count_path() {
	printf '%s/%s.fails\n' "${STATE_DIR}" "$1"
}

check_and_maybe_restart() {
	name="$1"
	path="$(fail_count_path "${name}")"
	fails=0
	if [ -f "${path}" ]; then
		fails="$(tr -d '[:space:]' <"${path}" || echo 0)"
	fi

	if HEALTH_QUIET=1 "${SCRIPTS_DIR}/health.sh" --quiet "${name}"; then
		echo 0 >"${path}"
		return 0
	fi

	fails=$((fails + 1))
	echo "${fails}" >"${path}"
	echo "watchdog: ${name} unhealthy (${fails}/${WATCHDOG_FAILURES})"

	if [ "${fails}" -lt "${WATCHDOG_FAILURES}" ]; then
		return 0
	fi

	echo "watchdog: restarting ${name}"
	run_as_root "$(mvm_bin)" restart "${name}" || true
	echo 0 >"${path}"
	sleep 2
	if HEALTH_QUIET=1 "${SCRIPTS_DIR}/health.sh" --quiet "${name}"; then
		echo "watchdog: ${name} recovered"
	else
		echo "watchdog: ${name} still unhealthy after restart"
	fi
}

scan_once() {
	if [ -n "${FILTER}" ]; then
		check_and_maybe_restart "${FILTER}"
		return 0
	fi
	for dir in "${INSTANCES_DIR}"/*/; do
		name="$(basename "${dir}")"
		[ -f "${dir}/config.env" ] || continue
		check_and_maybe_restart "${name}"
	done
}

if [ "${ONCE}" = "1" ]; then
	scan_once
	exit 0
fi

echo "watchdog interval=${WATCHDOG_INTERVAL}s failures=${WATCHDOG_FAILURES}"
while true; do
	scan_once || true
	sleep "${WATCHDOG_INTERVAL}"
done
