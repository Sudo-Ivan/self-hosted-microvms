#!/bin/sh
# Print access URLs for one instance or all instances.
#
# Usage:
#   ./scripts/urls.sh
#   ./scripts/urls.sh <name>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

print_one() {
	name="$1"

	load_instance "${name}"
	if is_running "${PID_FILE}"; then
		state="running"
	else
		state="stopped"
	fi

	scheme="${HEALTH_SCHEME:-http}"
	host_port="${HEALTH_PORT:-}"
	if [ -z "${host_port}" ] && [ -n "${PORT_FORWARDS:-}" ]; then
		first="${PORT_FORWARDS%%,*}"
		first="$(echo "${first}" | tr -d '[:space:]')"
		host_port="${first%%:*}"
	fi

	host_url="-"
	guest_url="-"
	if [ -n "${host_port}" ]; then
		host_url="${scheme}://127.0.0.1:${host_port}/"
		guest_url="${scheme}://${GUEST_IP}:${host_port}/"
	fi

	printf '%-14s %-10s %-36s %s\n' "${name}" "${state}" "${host_url}" "${guest_url}"
}

printf '%-14s %-10s %-36s %s\n' "INSTANCE" "STATE" "HOST_URL" "GUEST_URL"
printf '%s\n' "--------------------------------------------------------------------------------"

if [ -n "${1:-}" ]; then
	print_one "$1"
	exit 0
fi
found=0
for dir in "${INSTANCES_DIR}"/*/; do
	name="$(basename "${dir}")"
	[ -f "${dir}/config.env" ] || continue
	print_one "${name}"
	found=1
done
if [ "${found}" -eq 0 ]; then
	echo "(no instances)"
fi
