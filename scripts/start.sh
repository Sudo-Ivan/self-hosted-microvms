#!/bin/sh
# Start a microvm instance.
#
# Usage:
#   ./scripts/start.sh <name>
#   DETACH=0 ./scripts/start.sh <name>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
load_config

NAME="${1:-}"
[ -n "${NAME}" ] || die "usage: $0 <name>"
load_instance "${NAME}"

require_cmd "${FIRECRACKER_BIN}"
[ -r /dev/kvm ] || die "/dev/kvm is not readable (add user to kvm group)"
[ -f "${KERNEL_PATH}" ] || die "missing kernel: ${KERNEL_PATH}"
[ -f "${ROOTFS_PATH}" ] || die "missing rootfs: ${ROOTFS_PATH}"
[ -f "${DATA_PATH}" ] || die "missing data volume: ${DATA_PATH}"

if is_running "${PID_FILE}"; then
	die "instance already running (pid $(cat "${PID_FILE}")). stop with: $(root_helper 2>/dev/null || echo sudo) ./mvm stop ${NAME}"
fi

DETACH="${DETACH:-1}"
SETUP_NET="${SETUP_NET:-1}"
TAP_FOR_VM="${TAP_DEV}"

if [ "${SETUP_NET}" = "1" ]; then
	[ "$(id -u)" -eq 0 ] || die "start needs root for networking ($(root_helper 2>/dev/null || echo sudo) ./mvm start ${NAME})"
	setup_tap "${TAP_DEV}"
	# shellcheck source=../argus/lib.sh
	. "${REPO_ROOT}/argus/lib.sh"
	argus_load_global_policy
	if [ "${ARGUS_ENABLED}" = "1" ]; then
		# Always refresh policy so new guests and ports are live.
		info "applying Argus firewall and DNS"
		argus_apply
	else
		enable_masquerade
		apply_port_forwards "${GUEST_IP}" "${PORT_FORWARDS}"
	fi
else
	TAP_FOR_VM=""
	echo "SETUP_NET=0 skipping TAP and port forwards"
fi

# Refresh template + guest scripts into rootfs on every privileged start.
# shellcheck source=../lib/shares.sh
. "${LIB_DIR}/shares.sh"
# shellcheck source=../lib/guestfs.sh
. "${LIB_DIR}/guestfs.sh"
if [ "$(id -u)" -eq 0 ]; then
	if [ -n "${HOST_SHARES:-}" ]; then
		shares_apply_host_exports
		shares_write_guest_file
	else
		guestfs_sync_template
	fi
fi

rm -f "${API_SOCK}" "${VSOCK_UDS}" "${VSOCK_UDS}_"* "${CONFIG_PATH}"
: >"${LOG_PATH}"
: >"${STDOUT_PATH}"
: >"${STDERR_PATH}"

BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off nomodules root=/dev/vda rw init=/init"
if [ -n "${MICROVM_MODE:-}" ]; then
	BOOT_ARGS="${BOOT_ARGS} microvm.mode=${MICROVM_MODE}"
fi

WANT_SECRETS=0
if mvmsec_resolve >/dev/null 2>&1; then
	if MVM_SHARED_DIR="${SHARED_DIR}" "$(mvmsec_resolve)" exists "${NAME}" --shared-dir "${SHARED_DIR}" 2>/dev/null; then
		WANT_SECRETS=1
	fi
fi
if [ "${WANT_SECRETS}" = "1" ] && [ -z "${TAP_FOR_VM}" ]; then
	die "instance ${NAME} has secrets but SETUP_NET=0 (MMDS needs eth0)"
fi

python3 - "${CONFIG_PATH}" "${KERNEL_PATH}" "${ROOTFS_PATH}" "${DATA_PATH}" \
	"${BOOT_ARGS}" "${VCPU_COUNT}" "${MEM_MIB}" "${GUEST_CID}" "${VSOCK_UDS}" \
	"${LOG_PATH}" "${TAP_FOR_VM}" "${TAP_MAC}" "${WANT_SECRETS}" <<'PY'
import json
import sys

(
    config_path,
    kernel,
    rootfs,
    data,
    boot_args,
    vcpu_count,
    mem_mib,
    guest_cid,
    vsock_uds,
    log_path,
    tap_dev,
    tap_mac,
    want_secrets,
) = sys.argv[1:]

cfg = {
    "boot-source": {
        "kernel_image_path": kernel,
        "boot_args": boot_args,
    },
    "drives": [
        {
            "drive_id": "rootfs",
            "path_on_host": rootfs,
            "is_root_device": True,
            "is_read_only": False,
        },
        {
            "drive_id": "data",
            "path_on_host": data,
            "is_root_device": False,
            "is_read_only": False,
        },
    ],
    "machine-config": {
        "vcpu_count": int(vcpu_count),
        "mem_size_mib": int(mem_mib),
        "smt": False,
    },
    "vsock": {
        "guest_cid": int(guest_cid),
        "uds_path": vsock_uds,
    },
    "logger": {
        "log_path": log_path,
        "level": "Info",
        "show_level": True,
        "show_log_origin": False,
    },
}

if tap_dev:
    cfg["network-interfaces"] = [
        {
            "iface_id": "eth0",
            "guest_mac": tap_mac,
            "host_dev_name": tap_dev,
        }
    ]
    if want_secrets == "1":
        cfg["mmds-config"] = {
            "version": "V2",
            "network_interfaces": ["eth0"],
        }

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PY

# Wait for the Firecracker API socket then PUT MMDS secrets.
inject_mmds_secrets() {
	_mvmsec=
	_mmds_tmp=
	_i=0
	_mvmsec="$(mvmsec_resolve)" || die "mvmsec required to inject secrets"
	require_cmd curl
	while [ "${_i}" -lt 10 ]; do
		if [ -S "${API_SOCK}" ]; then
			break
		fi
		_i=$((_i + 1))
		sleep 1
	done
	[ -S "${API_SOCK}" ] || die "Firecracker API socket not ready: ${API_SOCK}"
	_mmds_tmp="$(mktemp "${INSTANCE_DIR}/mmds.XXXXXX")"
	chmod 600 "${_mmds_tmp}"
	if ! "${_mvmsec}" export-mmds "${NAME}" --shared-dir "${SHARED_DIR}" >"${_mmds_tmp}"; then
		rm -f "${_mmds_tmp}"
		die "export-mmds failed"
	fi
	# Ensure MMDS V2 is enabled on eth0 (config-file may already set this).
	if ! curl --unix-socket "${API_SOCK}" -sS -X PUT "http://localhost/mmds/config" \
		-H "Content-Type: application/json" \
		-d '{"version":"V2","network_interfaces":["eth0"]}' >/dev/null; then
		rm -f "${_mmds_tmp}"
		die "failed to configure MMDS"
	fi
	if ! curl --unix-socket "${API_SOCK}" -sS -X PUT "http://localhost/mmds" \
		-H "Content-Type: application/json" \
		--data-binary @"${_mmds_tmp}" >/dev/null; then
		rm -f "${_mmds_tmp}"
		die "failed to put MMDS secrets"
	fi
	rm -f "${_mmds_tmp}"
	info "injected secrets into MMDS for ${NAME}"
}

info "starting ${INSTANCE_NAME}"
echo "  kernel=${KERNEL_PATH}"
echo "  rootfs=${ROOTFS_PATH}"
echo "  data=${DATA_PATH}"
echo "  guest_ip=${GUEST_IP}"
echo "  tap=${TAP_FOR_VM:-none}"
echo "  ports=${PORT_FORWARDS:-none}"
echo "  shares=${HOST_SHARES:-none}"
echo "  secrets=${WANT_SECRETS}"
echo "  log=${STDOUT_PATH}"

if [ "${DETACH}" = "1" ]; then
	"${FIRECRACKER_BIN}" \
		--api-sock "${API_SOCK}" \
		--config-file "${CONFIG_PATH}" \
		>"${STDOUT_PATH}" 2>"${STDERR_PATH}" &
	echo $! >"${PID_FILE}"
	echo "detached pid $(cat "${PID_FILE}")"
	if [ "${WANT_SECRETS}" = "1" ]; then
		inject_mmds_secrets
	fi
else
	"${FIRECRACKER_BIN}" \
		--api-sock "${API_SOCK}" \
		--config-file "${CONFIG_PATH}" \
		>"${STDOUT_PATH}" 2>"${STDERR_PATH}" &
	fc_pid=$!
	echo "${fc_pid}" >"${PID_FILE}"
	if [ "${WANT_SECRETS}" = "1" ]; then
		inject_mmds_secrets
	fi
	_start_on_signal() {
		"${SCRIPTS_DIR}/stop.sh" "${INSTANCE_NAME}" >/dev/null 2>&1 || true
	}
	trap _start_on_signal INT TERM
	tail -n +1 -F "${STDOUT_PATH}" &
	tail_pid=$!
	wait "${fc_pid}" || true
	kill "${tail_pid}" 2>/dev/null || true
	rm -f "${PID_FILE}"
fi
