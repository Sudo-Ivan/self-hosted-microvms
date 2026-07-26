#!/bin/sh
# Scan Docker Compose projects and suggest or apply mvm templates.
#
# Usage:
#   ./scripts/migrate.sh [dir ...]
#   ./scripts/migrate.sh --no-wait ~/stacks

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
MIGRATE_DIR="${LIB_DIR}/migrate"
IMAGE_MAP="${MIGRATE_DIR}/image-map.json"
MATCH_PY="${MIGRATE_DIR}/compose-match.py"

WAIT_FLAG=""
DIRS=""

usage() {
	cat <<'EOF'
Usage:
  ./mvm migrate [dir ...]
  ./mvm migrate --no-wait [dir ...]

Scans for compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml
(max depth 2 per directory). Requires docker compose for config rendering.

Shows matched and skipped services, then asks to apply each match.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--no-wait)
		WAIT_FLAG="--no-wait"
		shift
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		DIRS="${DIRS} $1"
		shift
		;;
	esac
done

if [ -z "${DIRS}" ]; then
	DIRS="."
fi

if ! command -v docker >/dev/null 2>&1; then
	die "docker not found on PATH (needed for: docker compose config --format json)"
fi

if ! docker compose version >/dev/null 2>&1; then
	die "docker compose plugin not available"
fi

_tpl_list="$(each_template | tr '\n' ',' | sed 's/,$//')"
_meta_json="$(mktemp)"
_trap_files="${_meta_json}"
trap 'rm -f ${_trap_files}' EXIT INT HUP TERM

python3 - "${TEMPLATES_DIR}" "${_meta_json}" <<'PY'
import json
import pathlib
import re
import sys

templates_dir = pathlib.Path(sys.argv[1])
out_path = pathlib.Path(sys.argv[2])
meta = {}
for manifest in templates_dir.glob("*/manifest.env"):
    name = manifest.parent.name
    if name.startswith("_"):
        continue
    text = manifest.read_text()
    data_hint = ""
    example_share = ""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("DATA_HINT="):
            data_hint = line.split("=", 1)[1].strip().strip('"').strip("'")
        if line.startswith("EXAMPLE_SHARE="):
            example_share = line.split("=", 1)[1].strip().strip('"').strip("'")
    meta[name] = {"data_hint": data_hint, "example_share": example_share}
out_path.write_text(json.dumps(meta))
PY

_find_compose() {
	_dir="$1"
	_depth="${2:-0}"
	[ "${_depth}" -le 2 ] || return 0
	for _name in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
		if [ -f "${_dir}/${_name}" ]; then
			printf '%s\n' "${_dir}/${_name}"
		fi
	done
	if [ "${_depth}" -ge 2 ]; then
		return 0
	fi
	for _sub in "${_dir}"/*; do
		[ -d "${_sub}" ] || continue
		_find_compose "${_sub}" $((_depth + 1))
	done
}

compose_files=""
for _root in ${DIRS}; do
	[ -d "${_root}" ] || die "not a directory: ${_root}"
	_found="$(_find_compose "$(CDPATH= cd -- "${_root}" && pwd)" 0)"
	if [ -n "${_found}" ]; then
		compose_files="${compose_files}
${_found}"
	fi
done
compose_files="$(echo "${compose_files}" | sed '/^$/d' | sort -u)"

if [ -z "${compose_files}" ]; then
	die "no compose files found (looked for compose.yaml and docker-compose.yml)"
fi

_all_matched="$(mktemp)"
_all_skipped="$(mktemp)"
_trap_files="${_trap_files} ${_all_matched} ${_all_skipped}"
echo "[]" >"${_all_matched}"
echo "[]" >"${_all_skipped}"

while read -r _cf; do
	[ -n "${_cf}" ] || continue
	info "parsing ${_cf}"
	_cfg="$(mktemp)"
	_trap_files="${_trap_files} ${_cfg}"
	if ! docker compose -f "${_cf}" config --format json >"${_cfg}" 2>/dev/null; then
		echo "warn: docker compose config failed for ${_cf}" >&2
		continue
	fi
	_out="$(mktemp)"
	_trap_files="${_trap_files} ${_out}"
	python3 "${MATCH_PY}" \
		--image-map "${IMAGE_MAP}" \
		--compose-file "${_cf}" \
		--templates "${_tpl_list}" \
		--template-meta "${_meta_json}" \
		"${_cfg}" >"${_out}"
	python3 - "${_all_matched}" "${_all_skipped}" "${_out}" <<'PY'
import json
import pathlib
import sys

am = pathlib.Path(sys.argv[1])
sk = pathlib.Path(sys.argv[2])
part = pathlib.Path(sys.argv[3])
data = json.loads(part.read_text())
cur_m = json.loads(am.read_text())
cur_s = json.loads(sk.read_text())
cur_m.extend(data.get("matched", []))
cur_s.extend(data.get("skipped", []))
am.write_text(json.dumps(cur_m, indent=2))
sk.write_text(json.dumps(cur_s, indent=2))
PY
done <<EOF
${compose_files}
EOF

_m_count="$(python3 -c "import json; print(len(json.load(open('${_all_matched}'))))")"
_s_count="$(python3 -c "import json; print(len(json.load(open('${_all_skipped}'))))")"

echo
echo "matched (${_m_count}):"
printf '%-40s %-14s %-22s %s\n' "COMPOSE" "SERVICE" "TEMPLATE" "IMAGE"
printf '%s\n' "--------------------------------------------------------------------------------"

python3 - "${_all_matched}" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
for row in data:
    cf = row.get("compose_file", "")
    if len(cf) > 38:
        cf = "..." + cf[-35:]
    print(f"{cf:<40} {row.get('service',''):<14} {row.get('template',''):<22} {row.get('image','')}")
    for hint in row.get("share_hints") or []:
        print(f"  share hint: --share {hint}")
    print(f"  suggest:    ./mvm up {row.get('instance','')} {row.get('template','')}")
PY

echo
echo "skipped (${_s_count}):"
python3 - "${_all_skipped}" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1]))
for row in data:
    img = row.get("image", "")
    extra = f"  image={img}" if img else ""
    print(f"  {row.get('compose_file','')}: {row.get('service','')} ({row.get('reason','')}){extra}")
PY

if [ "${_m_count}" -eq 0 ]; then
	exit 0
fi

echo
python3 - "${_all_matched}" <<'PY' | while read -r line; do
import json
import sys
for row in json.load(open(sys.argv[1])):
    print(json.dumps(row))
PY
	_cf="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["compose_file"])')"
	_svc="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["service"])')"
	_tpl="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["template"])')"
	_inst="$(echo "${line}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["instance"])')"
	_hints="$(echo "${line}" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("share_hints") or []))')"

	printf 'Apply %s as instance %s (template %s)? [y/N] ' "${_svc}" "${_inst}" "${_tpl}" >&2
	read -r _ans
	case "${_ans}" in
	y | Y | yes | YES)
		_share_args=""
		if [ -n "${_hints}" ]; then
			printf 'Add suggested volume shares? [y/N] ' >&2
			read -r _sh
			case "${_sh}" in
			y | Y | yes | YES)
				_hint_file="$(mktemp)"
				printf '%s\n' "${_hints}" >"${_hint_file}"
				while read -r _hint; do
					[ -n "${_hint}" ] || continue
					_host_part="${_hint%%:*}"
					_rest="${_hint#*:}"
					case "${_host_part}" in
					./*)
						_compose_dir="$(dirname -- "${_cf}")"
						_host_part="${_compose_dir}/${_host_part#./}"
						;;
					esac
					_guest_part="${_rest%%:*}"
					_mode="${_rest#*:}"
					case "${_mode}" in
					"${_guest_part}") _mode="rw" ;;
					esac
					printf 'host path for %s [%s]: ' "${_guest_part}" "${_host_part}" >&2
					read -r _host_in
					if [ -z "${_host_in}" ]; then
						_host_in="${_host_part}"
					fi
					_share_args="${_share_args} --share ${_host_in}:${_guest_part}:${_mode}"
				done <"${_hint_file}"
				rm -f "${_hint_file}"
				;;
			esac
		fi
		# shellcheck disable=SC2086
		"${SCRIPTS_DIR}/up.sh" "${_inst}" "${_tpl}" ${WAIT_FLAG} ${_share_args}
		;;
	*)
		echo "skip ${_svc}" >&2
		;;
	esac
done
