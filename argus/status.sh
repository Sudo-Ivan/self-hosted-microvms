#!/bin/sh
# Show Argus policy, DNS queries, and live guest connections.
#
# Usage:
#   ./argus/status.sh
#   ./argus/status.sh <name>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
# shellcheck source=lib.sh
. "${REPO_ROOT}/argus/lib.sh"
load_config
argus_load_global_policy

FILTER_NAME="${1:-}"

echo "Argus"
echo "  enabled:        ${ARGUS_ENABLED}"
echo "  default_egress: ${ARGUS_DEFAULT_EGRESS}"
echo "  inter_vm:       ${ARGUS_INTER_VM}"
echo "  log_drops:      ${ARGUS_LOG_DROPS}"
echo "  policy_file:    ${ARGUS_POLICY_FILE}"
echo

if nft list table inet "${ARGUS_NFT_TABLE}" >/dev/null 2>&1; then
	echo "nft table inet ${ARGUS_NFT_TABLE}: present"
else
	echo "nft table inet ${ARGUS_NFT_TABLE}: missing (run sudo ./mvm argus apply)"
fi
echo

argus_dns_status
echo

printf '%-14s %-16s %-10s %-24s %s\n' "INSTANCE" "GUEST_IP" "STATE" "EGRESS" "PEERS"
printf '%s\n' "------------------------------------------------------------------------------"

while IFS="$(printf '\t')" read -r name ip tap ports; do
	[ -n "${name}" ] || continue
	if [ -n "${FILTER_NAME}" ] && [ "${name}" != "${FILTER_NAME}" ]; then
		continue
	fi

	argus_load_instance_firewall "${name}"
	state="stopped"
	if is_running "$(instance_dir "${name}")/firecracker.pid"; then
		state="running"
	fi

	if [ -n "${EGRESS_ALLOW:-}" ]; then
		egress="${EGRESS_ALLOW}"
	else
		egress="default(${ARGUS_DEFAULT_EGRESS})"
	fi
	peers="${ALLOW_PEERS:-none}"

	printf '%-14s %-16s %-10s %-24s %s\n' \
		"${name}" "${ip}" "${state}" "${egress}" "${peers}"
done <<EOF
$(argus_foreach_instance)
EOF

echo
echo "Recent DNS queries"
printf '%s\n' "------------------------------------------------------------------------------"
argus_dns_show_queries "${ARGUS_DNS_QUERY_LINES}" "${FILTER_NAME}"

echo
echo "Active connections (guest related)"
printf '%-10s %-5s %-20s %-20s %-28s %s\n' "INSTANCE" "PROTO" "SRC" "DST" "DOMAIN" "STATE"
printf '%s\n' "---------------------------------------------------------------------------------------------"

if ! command -v conntrack >/dev/null 2>&1; then
	echo "(install conntrack-tools for live flow listing)"
	exit 0
fi

argus_dns_dirs
_rows_file=$(mktemp)
argus_foreach_instance >"${_rows_file}"
python3 - "${SUBNET_PREFIX}" "${FILTER_NAME}" "${ARGUS_DNS_IPMAP}" "${_rows_file}" <<'PY'
import subprocess
import sys
from pathlib import Path

subnet = sys.argv[1] + "."
filter_name = sys.argv[2]
ipmap_path = sys.argv[3]
rows = Path(sys.argv[4]).read_text(encoding="utf-8", errors="replace").splitlines()
ip_to_name = {}
for row in rows:
    parts = row.split("\t")
    if len(parts) >= 2 and parts[1]:
        ip_to_name[parts[1]] = parts[0]

ip_to_domain = {}
p = Path(ipmap_path)
if p.is_file():
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        if "\t" not in line:
            continue
        ip, domain = line.split("\t", 1)
        ip_to_domain[ip.strip()] = domain.strip()

try:
    out = subprocess.check_output(["conntrack", "-L"], stderr=subprocess.DEVNULL, text=True)
except Exception:
    print("(conntrack needs root for full visibility)")
    raise SystemExit(0)

def fields(line: str):
    d = {}
    for tok in line.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            d.setdefault(k, v)
    return d

seen = set()
for line in out.splitlines():
    parts = line.split()
    if not parts:
        continue
    proto = parts[0]
    f = fields(line)
    src = f.get("src", "")
    dst = f.get("dst", "")
    sport = f.get("sport", "")
    dport = f.get("dport", "")
    state = f.get("state", "-")
    if not (src.startswith(subnet) or dst.startswith(subnet)):
        continue
    key = (proto, src, sport, dst, dport, state)
    if key in seen:
        continue
    seen.add(key)
    src_name = ip_to_name.get(src, src)
    dst_name = ip_to_name.get(dst, dst)
    if filter_name and filter_name not in (src_name, dst_name):
        continue
    if src in ip_to_name:
        label = src_name
    elif dst in ip_to_name:
        label = dst_name
    else:
        label = "-"
    domain = ip_to_domain.get(dst) or ip_to_domain.get(src) or "-"
    print(
        f"{label:<10} {proto:<5} {src + ':' + sport:<20} "
        f"{dst + ':' + dport:<20} {domain:<28} {state}"
    )
PY
rm -f "${_rows_file}"
