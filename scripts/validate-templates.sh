#!/bin/sh
# Validate template layout and manifests.
#
# Usage:
#   ./scripts/validate-templates.sh
#   ./scripts/validate-templates.sh --quiet

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

QUIET=0
for arg in "$@"; do
	case "${arg}" in
	--quiet|-q) QUIET=1 ;;
	-*)
		die "unknown flag: ${arg}"
		;;
	esac
done

pass=0
fail=0

ok() {
	[ "${QUIET}" = "1" ] || echo "ok    $*"
	pass=$((pass + 1))
}

bad() {
	echo "FAIL  $*" >&2
	fail=$((fail + 1))
}
count=0
while read -r name; do
	count=$((count + 1))
	dir="$(template_dir "${name}")"
	before_fail="${fail}"

	[ -f "${dir}/manifest.env" ] || {
		bad "${name}: missing manifest.env"
		continue
	}
	[ -f "${dir}/install.sh" ] || bad "${name}: missing install.sh"
	[ -f "${dir}/run.sh" ] || bad "${name}: missing run.sh"
	[ -x "${dir}/install.sh" ] || bad "${name}: install.sh not executable"
	[ -x "${dir}/run.sh" ] || bad "${name}: run.sh not executable"

	DESCRIPTION=""
	PORT_FORWARDS=""
	PACKAGES=""
	MEM_MIB=""
	TAGS=""
	HEALTH_SCHEME=""
	HARDEN=""
	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${dir}/manifest.env"
	set +a

	[ -n "${DESCRIPTION:-}" ] || bad "${name}: DESCRIPTION empty"
	[ -n "${MEM_MIB:-}" ] || bad "${name}: MEM_MIB empty"
	[ -n "${TAGS:-}" ] || bad "${name}: TAGS empty (comma-separated)"
	case "${HEALTH_SCHEME:-http}" in
	http|https) ;;
	*) bad "${name}: HEALTH_SCHEME must be http or https" ;;
	esac

	case "${HARDEN:-setpriv}" in
	setpriv|user|caps|bwrap|bubblewrap|off|0|no|false|"") ;;
	*) bad "${name}: HARDEN must be setpriv, bwrap, or off" ;;
	esac

	# Install scripts should pin or document upstream when downloading.
	if grep -qE 'download_url|curl .*github|pip install|git clone' "${dir}/install.sh" 2>/dev/null; then
		if ! grep -qE '^[A-Z0-9_]+_(VERSION|CHANNEL)=' "${dir}/install.sh" \
			&& ! grep -qE 'VERSION="\$\{[A-Z0-9_]+_VERSION' "${dir}/install.sh" \
			&& ! grep -qE 'apk add' "${dir}/install.sh" \
			&& ! grep -qE '_(VERSION|CHANNEL):-' "${dir}/install.sh"; then
			bad "${name}: download/install without VERSION/CHANNEL pin variable"
		fi
	fi

	# No obvious secrets in template tree (skip generated/random assignments).
	_scan_out="/tmp/mvm-secret-scan.$$"
	if python3 - "${dir}" "${_scan_out}" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
pat = re.compile(
    r'(password|secret|api[_-]?key|token)\s*=\s*["\'][^"$`\']{8,}',
    re.I,
)
skip = re.compile(
    r'ultrasecretkey|example|changeme|placeholder|GENERATED|admin\.pass|jwt\.secret|master\.key',
    re.I,
)
hits = []
for path in root.rglob('*'):
    if not path.is_file():
        continue
    if path.suffix not in {'.env', '.sh', '.yml', '.yaml', '.ini'}:
        continue
    try:
        text = path.read_text(errors='replace')
    except OSError:
        continue
    for i, line in enumerate(text.splitlines(), 1):
        if pat.search(line) and not skip.search(line):
            hits.append(f'{path}:{i}:{line}')
out.write_text('\n'.join(hits) + ('\n' if hits else ''))
sys.exit(0 if hits else 1)
PY
	then
		if [ -s "${_scan_out}" ]; then
			bad "${name}: possible hardcoded secret"
			[ "${QUIET}" = "1" ] || cat "${_scan_out}" >&2
		fi
	fi
	rm -f "${_scan_out}"

	if [ "${fail}" -eq "${before_fail}" ]; then
		ok "${name}"
	fi
done <<EOF
$(each_template)
EOF

[ "${count}" -gt 0 ] || die "no templates found"

[ "${QUIET}" = "1" ] || {
	echo
	echo "templates: ${count}  ok=${pass}  fail=${fail}"
}

[ "${fail}" -eq 0 ]
