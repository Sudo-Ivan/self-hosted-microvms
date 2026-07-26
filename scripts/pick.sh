#!/bin/sh
# Interactive template picker (fzf or numbered menu).
#
# Usage:
#   ./scripts/pick.sh [--tag=NAME]
# Prints chosen template name on stdout.

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

FILTER_TAG=""
for arg in "$@"; do
	case "${arg}" in
	--tag=*)
		FILTER_TAG="${arg#--tag=}"
		;;
	-h | --help)
		cat <<'EOF'
Usage:
  ./mvm pick [--tag=NAME]
  ./mvm templates --pick [--tag=NAME]
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

_tmp="$(mktemp)"
trap 'rm -f "${_tmp}"' EXIT INT HUP TERM

while read -r _pk_name; do
	load_template "${_pk_name}"
	if [ -n "${FILTER_TAG}" ] && ! template_has_tag "${FILTER_TAG}" "${TEMPLATE_TAGS}"; then
		continue
	fi
	_pk_desc="${TEMPLATE_DESCRIPTION:-}"
	printf '%s\t%s\n' "${_pk_name}" "${_pk_desc}"
done <<EOF >>"${_tmp}"
$(each_template)
EOF

if [ ! -s "${_tmp}" ]; then
	die "no templates match"
fi

if command -v fzf >/dev/null 2>&1; then
	choice="$(cut -f1 "${_tmp}" | fzf --height=40% --reverse --prompt='template> ')" || exit 1
	printf '%s\n' "${choice}"
	exit 0
fi

echo "Select a template:" >&2
_n=0
while IFS="$(printf '\t')" read -r _pk_name _pk_desc; do
	_n=$((_n + 1))
	printf '  %2d) %-16s %s\n' "${_n}" "${_pk_name}" "${_pk_desc}" >&2
	printf '%s\n' "${_pk_name}"
done <"${_tmp}" >"${_tmp}.names"

printf 'number (1-%d): ' "${_n}" >&2
read -r _pick_num
case "${_pick_num}" in
'' | *[!0-9]*)
	die "cancelled"
	;;
esac
if [ "${_pick_num}" -lt 1 ] || [ "${_pick_num}" -gt "${_n}" ]; then
	die "invalid choice"
fi
sed -n "${_pick_num}p" "${_tmp}.names"
