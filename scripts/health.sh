#!/bin/sh
# Healthcheck one instance or all instances.
#
# Usage:
#   ./scripts/health.sh
#   ./scripts/health.sh <name>
#   ./scripts/health.sh <name> --wait

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

WAIT=0
QUIET=0
NAME=""
for arg in "$@"; do
	case "${arg}" in
	--wait) WAIT=1 ;;
	--quiet|-q) QUIET=1 ;;
	-*)
		die "unknown flag: ${arg}"
		;;
	*)
		NAME="${arg}"
		;;
	esac
done

if [ "${QUIET}" = "1" ]; then
	HEALTH_QUIET=1
fi

probe_url() {
	_pu_url="$1"
	_pu_timeout="$2"
	_pu_insecure="${3:-0}"
	if [ "${_pu_insecure}" = "1" ]; then
		curl -sS -o /dev/null -w '%{http_code}' --connect-timeout "${_pu_timeout}" --max-time 3 --insecure "${_pu_url}" 2>/dev/null || echo "000"
	else
		curl -sS -o /dev/null -w '%{http_code}' --connect-timeout "${_pu_timeout}" --max-time 3 "${_pu_url}" 2>/dev/null || echo "000"
	fi
}

check_one() {
	name="$1"
	quiet="${HEALTH_QUIET:-0}"

	load_instance "${name}"

	if ! is_running "${PID_FILE}"; then
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "down" "firecracker not running"
		return 1
	fi

	health_path="${HEALTH_PATH:-/}"
	health_scheme="${HEALTH_SCHEME:-http}"
	case "${health_scheme}" in
	http|https) ;;
	*)
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "unhealthy" "invalid HEALTH_SCHEME=${health_scheme}"
		return 1
		;;
	esac

	# Accept self-signed and hostname-mismatched certs by default for https.
	# Set HEALTH_TLS_VERIFY=1 to require a trusted certificate.
	insecure=0
	if [ "${health_scheme}" = "https" ] && [ "${HEALTH_TLS_VERIFY:-0}" != "1" ]; then
		insecure=1
	fi

	host_port="${HEALTH_PORT:-}"
	if [ -z "${host_port}" ] && [ -n "${PORT_FORWARDS:-}" ]; then
		first="${PORT_FORWARDS%%,*}"
		first="$(echo "${first}" | tr -d '[:space:]')"
		host_port="${first%%:*}"
	fi

	if [ -z "${host_port}" ]; then
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "up" "running (no health port)"
		return 0
	fi

	timeout=1
	url="${health_scheme}://127.0.0.1:${host_port}${health_path}"
	code="$(probe_url "${url}" "${timeout}" "${insecure}")"

	if [ "${code}" = "000" ]; then
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "unhealthy" "no ${health_scheme} response on ${url}"
		return 1
	fi

	case "${code}" in
	2*|3*)
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "healthy" "${health_scheme} ${code} ${url}"
		return 0
		;;
	*)
		[ "${quiet}" = "1" ] || printf '%-14s %-10s %s\n' "${name}" "unhealthy" "${health_scheme} ${code} ${url}"
		return 1
		;;
	esac
}

wait_one() {
	name="$1"
	load_instance "${name}"
	wait_secs="${HEALTH_WAIT_SECS:-180}"
	case "${wait_secs}" in
	*[!0-9]*|'') wait_secs=120 ;;
	esac
	if [ "${wait_secs}" -lt 10 ]; then
		wait_secs=180
	fi
	max_iters=$(( (wait_secs + 1) / 2 ))
	for i in $(seq 1 "${max_iters}"); do
		if HEALTH_QUIET=1 check_one "${name}"; then
			check_one "${name}"
			return 0
		fi
		load_instance "${name}"
		if ! is_running "${PID_FILE}"; then
			printf '%-14s %-10s %s\n' "${name}" "down" "firecracker exited while waiting"
			return 1
		fi
		sleep 2
	done
	check_one "${name}" || true
	return 1
}

if [ "${QUIET}" != "1" ]; then
	printf '%-14s %-10s %s\n' "INSTANCE" "HEALTH" "DETAIL"
	printf '%s\n' "---------------------------------------------------------------"
fi

rc=0
if [ -n "${NAME}" ]; then
	if [ "${WAIT}" = "1" ]; then
		wait_one "${NAME}" || rc=1
	else
		check_one "${NAME}" || rc=1
	fi
	exit "${rc}"
fi
found=0
for dir in "${INSTANCES_DIR}"/*/; do
	name="$(basename "${dir}")"
	[ -f "${dir}/config.env" ] || continue
	found=1
	check_one "${name}" || rc=1
done
if [ "${found}" -eq 0 ]; then
	echo "(no instances)"
fi
exit "${rc}"
