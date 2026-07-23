#!/bin/sh
# List available templates.
#
# Usage:
#   ./scripts/templates.sh
#   ./scripts/templates.sh --tag media
#   ./scripts/templates.sh --json
#   ./scripts/templates.sh --tags

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

FILTER_TAG=""
JSON=0
LIST_TAGS=0
for arg in "$@"; do
	case "${arg}" in
	--json) JSON=1 ;;
	--tags) LIST_TAGS=1 ;;
	--tag=*)
		FILTER_TAG="${arg#--tag=}"
		;;
	--tag)
		die "use --tag=NAME"
		;;
	-h|--help)
		cat <<'EOF'
Usage:
  ./mvm templates
  ./mvm templates --tag=media
  ./mvm templates --json
  ./mvm templates --tags
EOF
		exit 0
		;;
	-*)
		die "unknown flag: ${arg}"
		;;
	*)
		die "unexpected argument: ${arg}"
		;;
	esac
done

if [ "${LIST_TAGS}" = "1" ]; then
	each_template | while read -r _tl_name; do
		load_template "${_tl_name}"
		_tl_old_ifs=${IFS}
		IFS=,
		for _tl_t in ${TEMPLATE_TAGS}; do
			IFS=${_tl_old_ifs}
			_tl_t="$(echo "${_tl_t}" | tr -d '[:space:]')"
			[ -n "${_tl_t}" ] && printf '%s\n' "${_tl_t}"
			IFS=,
		done
		IFS=${_tl_old_ifs}
	done | sort -u
	exit 0
fi

if [ "${JSON}" = "1" ]; then
	echo '['
	first=1
	while read -r name; do
		load_template "${name}"
		if [ -n "${FILTER_TAG}" ] && ! template_has_tag "${FILTER_TAG}" "${TEMPLATE_TAGS}"; then
			continue
		fi
		[ "${first}" = "1" ] || echo ','
		first=0
		python3 - "${name}" "${TEMPLATE_DESCRIPTION}" "${TEMPLATE_MEM_MIB}" "${TEMPLATE_PORT_FORWARDS}" "${TEMPLATE_TAGS}" "${TEMPLATE_HEALTH_SCHEME}" "${TEMPLATE_HEALTH_PORT}" "${TEMPLATE_HEALTH_PATH}" <<'PY'
import json,sys
name,desc,mem,ports,tags,scheme,hport,hpath=sys.argv[1:9]
obj={
  "name": name,
  "description": desc,
  "mem_mib": int(mem or 0),
  "port_forwards": ports,
  "tags": [t.strip() for t in tags.split(",") if t.strip()],
  "health": {"scheme": scheme or "http", "port": hport, "path": hpath or "/"},
}
print(json.dumps(obj), end="")
PY
	done <<EOF
$(each_template)
EOF
	echo
	echo ']'
	exit 0
fi

printf '%-16s %-8s %-18s %-22s %s\n' "TEMPLATE" "MEM" "PORTS" "TAGS" "DESCRIPTION"
printf '%s\n' "----------------------------------------------------------------------------------------------------"

while read -r name; do
	load_template "${name}"
	if [ -n "${FILTER_TAG}" ] && ! template_has_tag "${FILTER_TAG}" "${TEMPLATE_TAGS}"; then
		continue
	fi
	printf '%-16s %-8s %-18s %-22s %s\n' \
		"${name}" \
		"${TEMPLATE_MEM_MIB}M" \
		"${TEMPLATE_PORT_FORWARDS:-none}" \
		"${TEMPLATE_TAGS:-}" \
		"${TEMPLATE_DESCRIPTION:-}"
done <<EOF
$(each_template)
EOF
