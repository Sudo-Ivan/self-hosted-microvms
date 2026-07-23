#!/bin/sh
# Create a microvm instance from a template.
#
# Usage:
#   ./scripts/create.sh <name> <template>
#   ./scripts/create.sh vault vaultwarden
#   MEM_MIB=1024 PORT_FORWARDS=8443:80 ./scripts/create.sh vault vaultwarden

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config
ensure_shared
require_cmd truncate
require_cmd mkfs.ext4
require_cmd cp

NAME="${1:-}"
TEMPLATE="${2:-}"
if [ -z "${NAME}" ] || [ -z "${TEMPLATE}" ]; then
	die "usage: $0 <name> <template>"
fi
validate_name "${NAME}"

# Preserve caller overrides before profile and template manifests are sourced.
USER_GUEST_IP="${GUEST_IP:-}"
USER_MEM_MIB="${MEM_MIB:-}"
USER_VCPU_COUNT="${VCPU_COUNT:-}"
USER_DATA_SIZE_MIB="${DATA_SIZE_MIB:-}"
USER_ROOTFS_SIZE_MIB="${ROOTFS_SIZE_MIB:-}"
USER_PORT_FORWARDS="${PORT_FORWARDS:-}"
USER_TAP_DEV="${TAP_DEV:-}"
USER_HOST_SHARES="${HOST_SHARES:-}"
USER_PROFILE="${PROFILE:-}"

# shellcheck source=../lib/profiles.sh
. "${LIB_DIR}/profiles.sh"
if [ -n "${USER_PROFILE}" ]; then
	load_profile "${USER_PROFILE}"
	apply_profile_to_create_vars
fi

load_template "${TEMPLATE}"

DIR="$(instance_dir "${NAME}")"
[ ! -e "${DIR}" ] || die "instance already exists: ${NAME}"

[ -d "${SHARED_DIR}/base-staging" ] || die "base staging missing run ./scripts/build-base.sh first"
[ -f "${KERNEL_PATH}" ] || die "kernel missing run ./scripts/fetch-kernel.sh first"

OCTET="$(next_guest_ip_octet)"
if [ "${OCTET}" -gt 254 ]; then
	die "no free guest IPs left in ${SUBNET_PREFIX}.0/${GUEST_PREFIX}"
fi
CID="$(next_guest_cid)"
MAC="$(mac_from_octet "${OCTET}")"

GUEST_IP_VALUE="${USER_GUEST_IP:-${SUBNET_PREFIX}.${OCTET}}"
MEM_VALUE="${USER_MEM_MIB:-${TEMPLATE_MEM_MIB}}"
VCPU_VALUE="${USER_VCPU_COUNT:-${TEMPLATE_VCPU_COUNT}}"
DATA_SIZE="${USER_DATA_SIZE_MIB:-${TEMPLATE_DATA_SIZE_MIB}}"
ROOTFS_SIZE="${USER_ROOTFS_SIZE_MIB:-${TEMPLATE_ROOTFS_SIZE_MIB}}"
PORTS="${USER_PORT_FORWARDS:-${TEMPLATE_PORT_FORWARDS}}"
TAP_VALUE="${USER_TAP_DEV:-fc-${NAME}}"
SHARES_VALUE="${USER_HOST_SHARES:-}"
PROFILE_VALUE="${USER_PROFILE}"
HEALTH_PATH_VALUE="${TEMPLATE_HEALTH_PATH}"
HEALTH_PORT_VALUE="${TEMPLATE_HEALTH_PORT}"
HEALTH_SCHEME_VALUE="${TEMPLATE_HEALTH_SCHEME}"
HEALTH_TLS_VERIFY_VALUE="${TEMPLATE_HEALTH_TLS_VERIFY}"
HEALTH_WAIT_SECS_VALUE="${TEMPLATE_HEALTH_WAIT_SECS}"
if [ -z "${HEALTH_PORT_VALUE}" ] && [ -n "${PORTS}" ]; then
	first="${PORTS%%,*}"
	first="$(echo "${first}" | tr -d '[:space:]')"
	HEALTH_PORT_VALUE="${first%%:*}"
fi
case "${HEALTH_SCHEME_VALUE}" in
http|https) ;;
*)
	die "invalid HEALTH_SCHEME '${HEALTH_SCHEME_VALUE}' (use http or https)"
	;;
esac

info "creating instance ${NAME} from template ${TEMPLATE}"
mkdir -p "${DIR}/staging" "${DIR}/logs"

info "cloning base staging"
if command -v rsync >/dev/null 2>&1; then
	rsync -a --delete "${SHARED_DIR}/base-staging/" "${DIR}/staging/"
else
	rm -rf "${DIR}/staging"
	mkdir -p "${DIR}/staging"
	cp -a "${SHARED_DIR}/base-staging/." "${DIR}/staging/"
fi

mkdir -p "${DIR}/staging/opt/template"
cp -a "${TEMPLATE_DIR}/." "${DIR}/staging/opt/template/"
if [ -d "${TEMPLATES_DIR}/_common" ]; then
	mkdir -p "${DIR}/staging/opt/template/_common"
	cp -a "${TEMPLATES_DIR}/_common/." "${DIR}/staging/opt/template/_common/"
fi
chmod 755 "${DIR}/staging/opt/template/"*.sh 2>/dev/null || true
chmod 755 "${DIR}/staging/opt/template/_common/"*.sh 2>/dev/null || true
printf '%s\n' "${TEMPLATE}" >"${DIR}/staging/etc/microvm/template"
printf '%s\n' "${NAME}" >"${DIR}/staging/etc/microvm/instance"

# Always use the current guest PID 1 from the repo.
cp -f "${GUEST_DIR}/init" "${DIR}/staging/init"
cp -f "${GUEST_DIR}/first-boot.sh" "${DIR}/staging/etc/microvm/first-boot.sh"
cp -f "${GUEST_DIR}/run-service.sh" "${DIR}/staging/etc/microvm/run-service.sh"
cp -f "${GUEST_DIR}/update-guest.sh" "${DIR}/staging/etc/microvm/update-guest.sh"
cp -f "${GUEST_DIR}/mount-shares.sh" "${DIR}/staging/etc/microvm/mount-shares.sh"
cp -f "${GUEST_DIR}/fetch-secrets.sh" "${DIR}/staging/etc/microvm/fetch-secrets.sh"
cp -f "${GUEST_DIR}/prepare-harden.sh" "${DIR}/staging/etc/microvm/prepare-harden.sh"
cp -f "${GUEST_DIR}/harden-exec.sh" "${DIR}/staging/etc/microvm/harden-exec.sh"
chmod 755 \
	"${DIR}/staging/init" \
	"${DIR}/staging/etc/microvm/first-boot.sh" \
	"${DIR}/staging/etc/microvm/run-service.sh" \
	"${DIR}/staging/etc/microvm/update-guest.sh" \
	"${DIR}/staging/etc/microvm/mount-shares.sh" \
	"${DIR}/staging/etc/microvm/fetch-secrets.sh" \
	"${DIR}/staging/etc/microvm/prepare-harden.sh" \
	"${DIR}/staging/etc/microvm/harden-exec.sh"

cat >"${DIR}/staging/etc/microvm-net" <<EOF
GUEST_IP=${GUEST_IP_VALUE}
GUEST_PREFIX=${GUEST_PREFIX}
GATEWAY=${GATEWAY_IP}
DNS=${DNS}
EOF

# Instance metadata for guest scripts (no secrets).
cat >"${DIR}/staging/etc/microvm/instance.env" <<EOF
INSTANCE_NAME=${NAME}
TEMPLATE=${TEMPLATE}
GUEST_IP=${GUEST_IP_VALUE}
EOF

info "building rootfs (${ROOTFS_SIZE} MiB)"
truncate -s "${ROOTFS_SIZE}M" "${DIR}/rootfs.ext4"
mkfs.ext4 -q -F -d "${DIR}/staging" -L "mvm-${NAME}" "${DIR}/rootfs.ext4"

info "building data volume (${DATA_SIZE} MiB)"
truncate -s "${DATA_SIZE}M" "${DIR}/data.ext4"
DATA_STAGING="${DIR}/data-staging"
rm -rf "${DATA_STAGING}"
mkdir -p "${DATA_STAGING}/service"
if [ -d "${TEMPLATE_DIR}/data" ]; then
	cp -a "${TEMPLATE_DIR}/data/." "${DATA_STAGING}/"
fi
mkfs.ext4 -q -F -d "${DATA_STAGING}" -L "data-${NAME}" "${DIR}/data.ext4"
rm -rf "${DATA_STAGING}"

cat >"${DIR}/config.env" <<EOF
INSTANCE_NAME='${NAME}'
TEMPLATE='${TEMPLATE}'
GUEST_IP='${GUEST_IP_VALUE}'
GUEST_PREFIX='${GUEST_PREFIX}'
GATEWAY='${GATEWAY_IP}'
DNS='${DNS}'
TAP_DEV='${TAP_VALUE}'
TAP_MAC='${MAC}'
GUEST_CID='${CID}'
VCPU_COUNT='${VCPU_VALUE}'
MEM_MIB='${MEM_VALUE}'
DATA_SIZE_MIB='${DATA_SIZE}'
ROOTFS_SIZE_MIB='${ROOTFS_SIZE}'
PROFILE='${PROFILE_VALUE}'
PORT_FORWARDS='${PORTS}'
HOST_SHARES='${SHARES_VALUE}'
HEALTH_PATH='${HEALTH_PATH_VALUE}'
HEALTH_PORT='${HEALTH_PORT_VALUE}'
HEALTH_SCHEME='${HEALTH_SCHEME_VALUE}'
HEALTH_TLS_VERIFY='${HEALTH_TLS_VERIFY_VALUE}'
HEALTH_WAIT_SECS='${HEALTH_WAIT_SECS_VALUE}'
ROOTFS_PATH='${DIR}/rootfs.ext4'
DATA_PATH='${DIR}/data.ext4'
EOF

if [ -f "${TEMPLATE_DIR}/firewall.env" ]; then
	cp -f "${TEMPLATE_DIR}/firewall.env" "${DIR}/firewall.env"
else
	cp -f "${REPO_ROOT}/argus/firewall.example.env" "${DIR}/firewall.env"
fi

# Staging tree is large. Keep it for rebuilds unless CLEAN_STAGING=1.
if [ "${CLEAN_STAGING:-0}" = "1" ]; then
	rm -rf "${DIR}/staging"
fi

echo
echo "created instance ${NAME}"
echo "  template:  ${TEMPLATE}"
echo "  profile:   ${PROFILE_VALUE:-none}"
echo "  guest ip:  ${GUEST_IP_VALUE}"
echo "  tap:       ${TAP_VALUE}"
echo "  memory:    ${MEM_VALUE} MiB"
echo "  vcpu:      ${VCPU_VALUE}"
echo "  ports:     ${PORTS:-none}"
echo "  shares:    ${SHARES_VALUE:-none}"
echo "  config:    ${DIR}/config.env"
echo
echo "start with: ./mvm start ${NAME}"
