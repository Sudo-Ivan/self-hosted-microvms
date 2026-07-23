#!/bin/sh
# Check host prerequisites for running microvms.
#
# Usage:
#   ./scripts/doctor.sh
#   ./scripts/doctor.sh --shares

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NEED_SHARES=0
for arg in "$@"; do
	case "${arg}" in
	--shares) NEED_SHARES=1 ;;
	esac
done

pass=0
fail=0
warn=0

ok() {
	echo "ok    $*"
	pass=$((pass + 1))
}

bad() {
	echo "FAIL  $*"
	fail=$((fail + 1))
}

maybe() {
	echo "warn  $*"
	warn=$((warn + 1))
}

echo "MicroVM doctor"
echo

if command -v firecracker >/dev/null 2>&1; then
	ok "firecracker ($(firecracker --version 2>&1 | head -n1))"
else
	bad "firecracker not on PATH"
fi

if [ -r /dev/kvm ]; then
	ok "/dev/kvm readable"
else
	bad "/dev/kvm not readable (add user to kvm group)"
fi

for cmd in curl python3 tar truncate mkfs.ext4 ip nft; do
	if command -v "${cmd}" >/dev/null 2>&1; then
		ok "${cmd}"
	else
		bad "${cmd} missing"
	fi
done

if command -v doas >/dev/null 2>&1; then
	ok "doas (root helper)"
elif command -v sudo >/dev/null 2>&1; then
	ok "sudo (root helper)"
else
	maybe "neither doas nor sudo found (needed for non-root start/stop)"
fi

if command -v e2fsck >/dev/null 2>&1 && command -v resize2fs >/dev/null 2>&1; then
	ok "e2fsck/resize2fs (disk resize)"
else
	maybe "e2fsck/resize2fs missing (needed for ./mvm resize --data-mib)"
fi

if command -v dnsmasq >/dev/null 2>&1; then
	ok "dnsmasq (Argus DNS)"
else
	maybe "dnsmasq missing (needed for Argus DNS blocklists)"
fi

if command -v conntrack >/dev/null 2>&1; then
	ok "conntrack"
else
	maybe "conntrack missing (optional live flow listing)"
fi

if command -v exportfs >/dev/null 2>&1; then
	ok "exportfs (host shares)"
else
	if [ "${NEED_SHARES}" = "1" ]; then
		bad "exportfs missing install nfs-utils for HOST_SHARES"
	else
		maybe "exportfs missing (needed only for HOST_SHARES music/data folders)"
	fi
fi

if [ -f "${KERNEL_PATH}" ]; then
	ok "kernel ${KERNEL_PATH}"
else
	maybe "kernel missing run ./mvm setup"
fi

if [ -d "${SHARED_DIR}/base-staging" ]; then
	ok "base staging present"
else
	maybe "base staging missing run ./mvm setup"
fi

if [ -f "${ARGUS_DIR}/policy.env" ]; then
	ok "argus policy ${ARGUS_DIR}/policy.env"
else
	maybe "argus policy missing run ./mvm setup"
fi

if mvmsec_resolve >/dev/null 2>&1; then
	ok "mvmsec ($(mvmsec_resolve))"
	if [ -f "${SECRETS_DIR}/protect.json" ] || [ -f "${SECRETS_DIR}/vault.json.age" ]; then
		_prot="$("$(mvmsec_resolve)" protect status --shared-dir "${SHARED_DIR}" 2>/dev/null || true)"
		if [ -n "${_prot}" ]; then
			ok "secrets protect $(echo "${_prot}" | tr '\n' ' ')"
		fi
	fi
elif command -v go >/dev/null 2>&1; then
	maybe "mvmsec missing run ./scripts/build-mvmsec.sh"
else
	maybe "mvmsec missing and go not installed (needed for ./mvm secrets)"
fi

if [ -c /dev/tpmrm0 ] || [ -c /dev/tpm0 ]; then
	ok "TPM device present"
else
	maybe "no TPM device (optional for ./mvm secrets init TPM seal)"
fi

if [ -d "${SECRETS_DIR}" ]; then
	ok "secrets dir ${SECRETS_DIR}"
else
	maybe "secrets store not initialized (optional: ./mvm secrets init)"
fi

if "${SCRIPTS_DIR}/validate-templates.sh" --quiet; then
	ok "templates validate"
else
	maybe "templates validate failed run ./mvm validate"
fi

echo
echo "summary: ${pass} ok, ${warn} warnings, ${fail} failures"
if [ "${fail}" -gt 0 ]; then
	exit 1
fi
