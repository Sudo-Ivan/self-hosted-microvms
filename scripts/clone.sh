#!/bin/sh
# Clone a stopped instance to a new name with a fresh network identity.
#
# Usage:
#   ./scripts/clone.sh <src> <dst>
#   ./mvm clone navi navi2

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

SRC="${1:-}"
DST="${2:-}"
if [ -z "${SRC}" ] || [ -z "${DST}" ]; then
	die "usage: $0 <src> <dst>"
fi
validate_name "${SRC}"
validate_name "${DST}"
[ "${SRC}" != "${DST}" ] || die "src and dst must differ"

SRC_DIR="$(instance_dir "${SRC}")"
DST_DIR="$(instance_dir "${DST}")"
[ -d "${SRC_DIR}" ] || die "instance not found: ${SRC}"
[ ! -e "${DST_DIR}" ] || die "instance already exists: ${DST}"

load_instance "${SRC}"
if is_running "${PID_FILE}"; then
	die "stop ${SRC} before cloning (./mvm stop ${SRC})"
fi

[ -f "${ROOTFS_PATH}" ] || die "missing rootfs: ${ROOTFS_PATH}"
[ -f "${DATA_PATH}" ] || die "missing data: ${DATA_PATH}"

OCTET="$(next_guest_ip_octet)"
if [ "${OCTET}" -gt 254 ]; then
	die "no free guest IPs left in ${SUBNET_PREFIX}.0/${GUEST_PREFIX}"
fi
CID="$(next_guest_cid)"
MAC="$(mac_from_octet "${OCTET}")"
GUEST_IP_VALUE="${SUBNET_PREFIX}.${OCTET}"
TAP_VALUE="fc-${DST}"
GATEWAY_VALUE="${GATEWAY:-${GATEWAY_IP}}"
DNS_VALUE="${DNS:-1.1.1.1}"
PREFIX_VALUE="${GUEST_PREFIX:-24}"

info "cloning ${SRC} -> ${DST}"
mkdir -p "${DST_DIR}/logs"

cp -a "${ROOTFS_PATH}" "${DST_DIR}/rootfs.ext4"
cp -a "${DATA_PATH}" "${DST_DIR}/data.ext4"
if [ -f "${SRC_DIR}/firewall.env" ]; then
	cp -a "${SRC_DIR}/firewall.env" "${DST_DIR}/firewall.env"
fi
if [ -d "${SRC_DIR}/tls" ]; then
	cp -a "${SRC_DIR}/tls" "${DST_DIR}/tls"
fi

cat >"${DST_DIR}/config.env" <<EOF
INSTANCE_NAME='${DST}'
TEMPLATE='${TEMPLATE:-}'
GUEST_IP='${GUEST_IP_VALUE}'
GUEST_PREFIX='${PREFIX_VALUE}'
GATEWAY='${GATEWAY_VALUE}'
DNS='${DNS_VALUE}'
TAP_DEV='${TAP_VALUE}'
TAP_MAC='${MAC}'
GUEST_CID='${CID}'
VCPU_COUNT='${VCPU_COUNT}'
MEM_MIB='${MEM_MIB}'
DATA_SIZE_MIB='${DATA_SIZE_MIB:-}'
ROOTFS_SIZE_MIB='${ROOTFS_SIZE_MIB:-}'
PROFILE='${PROFILE:-}'
PORT_FORWARDS='${PORT_FORWARDS:-}'
HOST_SHARES='${HOST_SHARES:-}'
HEALTH_PATH='${HEALTH_PATH:-/}'
HEALTH_PORT='${HEALTH_PORT:-}'
HEALTH_SCHEME='${HEALTH_SCHEME:-http}'
HEALTH_TLS_VERIFY='${HEALTH_TLS_VERIFY:-0}'
HEALTH_WAIT_SECS='${HEALTH_WAIT_SECS:-}'
ROOTFS_PATH='${DST_DIR}/rootfs.ext4'
DATA_PATH='${DST_DIR}/data.ext4'
EOF

echo
echo "cloned ${SRC} -> ${DST}"
echo "  guest ip:  ${GUEST_IP_VALUE}"
echo "  tap:       ${TAP_VALUE}"
echo "  start:     ./mvm start ${DST}"
echo "  secrets:   not copied (set with ./mvm secrets set ${DST} KEY=...)"
