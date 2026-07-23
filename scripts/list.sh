#!/bin/sh
# Show status for one instance or all instances.
#
# Usage:
#   ./scripts/list.sh
#   ./scripts/list.sh <name>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

print_one() {
	name="$1"
	dir="$(instance_dir "${name}")"
	[ -f "${dir}/config.env" ] || return 0

	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${dir}/config.env"
	set +a

	pid=""
	state="stopped"
	if is_running "${dir}/firecracker.pid"; then
		pid="$(cat "${dir}/firecracker.pid")"
		state="running"
	fi

	ip="${GUEST_IP:-unknown}"
	ports="${PORT_FORWARDS:-none}"
	template="${TEMPLATE:-unknown}"
	mem="${MEM_MIB:-?}"

	printf '%-16s %-10s %-12s %-18s %-8s %s\n' \
		"${name}" "${state}" "${template}" "${ip}" "${mem}M" "${ports}"
	if [ -n "${pid}" ]; then
		printf '  pid %s\n' "${pid}"
	fi
}

printf '%-16s %-10s %-12s %-18s %-8s %s\n' \
	"NAME" "STATE" "TEMPLATE" "GUEST_IP" "MEM" "PORTS"
printf '%s\n' "--------------------------------------------------------------------"

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
