# Shared helpers for host-side microvm scripts.
# Source this file. Do not execute it directly.

set -eu

# Resolve repo root from the invoking script path ($0 stays the main script when libraries are sourced).
mvm_find_repo_root() {
	_mvm_d=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd) || return 1
	if [ -f "$_mvm_d/lib/common.sh" ]; then
		printf '%s\n' "$_mvm_d"
	elif [ -f "$_mvm_d/../lib/common.sh" ]; then
		CDPATH= cd -- "$_mvm_d/.." && pwd
	else
		echo "error: cannot find repo root from $1" >&2
		return 1
	fi
}

if [ -z "${REPO_ROOT:-}" ]; then
	REPO_ROOT=$(mvm_find_repo_root "$0") || exit 1
fi
SCRIPTS_DIR="${REPO_ROOT}/scripts"
LIB_DIR="${REPO_ROOT}/lib"
GUEST_DIR="${REPO_ROOT}/guest"
TEMPLATES_DIR="${REPO_ROOT}/templates"
SHARED_DIR="${REPO_ROOT}/shared"
INSTANCES_DIR="${REPO_ROOT}/instances"
CONFIG_FILE="${REPO_ROOT}/config.env"

die() {
	echo "error: $*" >&2
	exit 1
}

info() {
	echo "==> $*"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"
}

load_config() {
	if [ -f "${CONFIG_FILE}" ]; then
		# shellcheck disable=SC1090
		set -a
		# shellcheck disable=SC1091
		. "${CONFIG_FILE}"
		set +a
	fi

	FIRECRACKER_BIN="${FIRECRACKER_BIN:-firecracker}"
	KERNEL_SERIES="${KERNEL_SERIES:-6.1}"
	ALPINE_VERSION="${ALPINE_VERSION:-3.21}"
	BRIDGE_NAME="${BRIDGE_NAME:-fcbr0}"
	SUBNET_PREFIX="${SUBNET_PREFIX:-10.100.0}"
	GATEWAY_IP="${GATEWAY_IP:-${SUBNET_PREFIX}.1}"
	GUEST_PREFIX="${GUEST_PREFIX:-24}"
	DNS="${DNS:-1.1.1.1}"
	DEFAULT_MEM_MIB="${DEFAULT_MEM_MIB:-512}"
	DEFAULT_VCPU_COUNT="${DEFAULT_VCPU_COUNT:-1}"
	BASE_ROOTFS_SIZE_MIB="${BASE_ROOTFS_SIZE_MIB:-1024}"
	DEFAULT_DATA_SIZE_MIB="${DEFAULT_DATA_SIZE_MIB:-2048}"
	DEFAULT_PROFILE="${DEFAULT_PROFILE:-}"
	DETACH="${DETACH:-1}"
	SETUP_NET="${SETUP_NET:-1}"
	KERNEL_PATH="${KERNEL_PATH:-${SHARED_DIR}/vmlinux}"
	BASE_ROOTFS_PATH="${BASE_ROOTFS_PATH:-${SHARED_DIR}/base-rootfs.ext4}"
	ARGUS_ENABLED="${ARGUS_ENABLED:-1}"
	ARGUS_AUTO_APPLY="${ARGUS_AUTO_APPLY:-1}"
	ARGUS_DIR="${REPO_ROOT}/argus"
	ARGUS_POLICY_FILE="${ARGUS_POLICY_FILE:-${ARGUS_DIR}/policy.env}"
	BACKUPS_DIR="${BACKUPS_DIR:-${SHARED_DIR}/backups}"
	BACKUP_KEEP="${BACKUP_KEEP:-5}"
	WATCHDOG_INTERVAL="${WATCHDOG_INTERVAL:-30}"
	WATCHDOG_FAILURES="${WATCHDOG_FAILURES:-3}"
	PROFILES_DIR="${PROFILES_DIR:-${REPO_ROOT}/profiles}"
	MVMSEC_BIN="${MVMSEC_BIN:-${REPO_ROOT}/.tools/mvmsec}"
	SECRETS_DIR="${SECRETS_DIR:-${SHARED_DIR}/secrets}"
}

# Resolve the mvmsec binary. Prints path on success.
mvmsec_resolve() {
	if [ -n "${MVMSEC_BIN:-}" ] && [ -x "${MVMSEC_BIN}" ]; then
		printf '%s\n' "${MVMSEC_BIN}"
		return 0
	fi
	if [ -x "${REPO_ROOT}/.tools/mvmsec" ]; then
		printf '%s\n' "${REPO_ROOT}/.tools/mvmsec"
		return 0
	fi
	if command -v mvmsec >/dev/null 2>&1; then
		command -v mvmsec
		return 0
	fi
	return 1
}

root_helper() {
	# Prefer explicit override, then doas, then sudo.
	if [ -n "${MVM_ROOT_CMD:-}" ]; then
		printf '%s\n' "${MVM_ROOT_CMD}"
		return 0
	fi
	if command -v doas >/dev/null 2>&1; then
		printf '%s\n' doas
		return 0
	fi
	if command -v sudo >/dev/null 2>&1; then
		printf '%s\n' sudo
		return 0
	fi
	return 1
}

require_root() {
	_gr_helper=
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	if _gr_helper="$(root_helper)"; then
		die "needs root (try: ${_gr_helper} ${REPO_ROOT}/mvm $*)"
	fi
	die "needs root and neither doas nor sudo is available (set MVM_ROOT_CMD)"
}

run_as_root() {
	# Run a command as root via doas or sudo when needed.
	_gr_helper=
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
		return 0
	fi
	if _gr_helper="$(root_helper)"; then
		"${_gr_helper}" "$@"
		return 0
	fi
	die "needs root and neither doas nor sudo is available (set MVM_ROOT_CMD)"
}

# Re-exec the current script as root when needed. Pass original "$@".
# After passwordless doas/sudoers install, ./mvm start works without typing sudo.
ensure_root() {
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	if [ "${MVM_REEXEC:-0}" = "1" ]; then
		die "needs root (install passwordless access: ./mvm sudoers install or ./mvm doas install)"
	fi
	if ! root_helper >/dev/null 2>&1; then
		die "needs root and neither doas nor sudo is available (set MVM_ROOT_CMD, or ./mvm sudoers|doas install)"
	fi
	run_as_root env MVM_REEXEC=1 "$0" "$@"
	exit $?
}

# Prefer the passwordless wrapper when present (paths with spaces are unsupported in sudoers).
mvm_bin() {
	if [ -x /usr/local/sbin/mvm ]; then
		printf '%s\n' /usr/local/sbin/mvm
	else
		printf '%s\n' "${REPO_ROOT}/mvm"
	fi
}

instance_dir() {
	printf '%s/%s\n' "${INSTANCES_DIR}" "$1"
}

load_instance() {
	_load_name="$1"
	_load_dir=
	_load_dir="$(instance_dir "${_load_name}")"
	[ -d "${_load_dir}" ] || die "instance not found: ${_load_name}"
	[ -f "${_load_dir}/config.env" ] || die "missing ${_load_dir}/config.env"

	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${_load_dir}/config.env"
	set +a

	INSTANCE_NAME="${INSTANCE_NAME:-${_load_name}}"
	INSTANCE_DIR="${_load_dir}"
	ROOTFS_PATH="${ROOTFS_PATH:-${_load_dir}/rootfs.ext4}"
	DATA_PATH="${DATA_PATH:-${_load_dir}/data.ext4}"
	API_SOCK="${API_SOCK:-${_load_dir}/firecracker.sock}"
	VSOCK_UDS="${VSOCK_UDS:-${_load_dir}/vsock.sock}"
	PID_FILE="${PID_FILE:-${_load_dir}/firecracker.pid}"
	LOG_PATH="${LOG_PATH:-${_load_dir}/firecracker.log}"
	STDOUT_PATH="${STDOUT_PATH:-${_load_dir}/firecracker.stdout}"
	STDERR_PATH="${STDERR_PATH:-${_load_dir}/firecracker.stderr}"
	CONFIG_PATH="${CONFIG_PATH:-${_load_dir}/vm-config.json}"
	TAP_DEV="${TAP_DEV:-fc-${INSTANCE_NAME}}"
	TAP_MAC="${TAP_MAC:-AA:FC:00:00:00:01}"
	GUEST_CID="${GUEST_CID:-3}"
	VCPU_COUNT="${VCPU_COUNT:-1}"
	MEM_MIB="${MEM_MIB:-512}"
	GUEST_IP="${GUEST_IP:-${SUBNET_PREFIX}.10}"
	GATEWAY="${GATEWAY:-${GATEWAY_IP}}"
	PORT_FORWARDS="${PORT_FORWARDS:-}"
	HOST_SHARES="${HOST_SHARES:-}"
	HEALTH_PATH="${HEALTH_PATH:-/}"
	HEALTH_PORT="${HEALTH_PORT:-}"
	HEALTH_SCHEME="${HEALTH_SCHEME:-http}"
	HEALTH_TLS_VERIFY="${HEALTH_TLS_VERIFY:-0}"
	HEALTH_WAIT_SECS="${HEALTH_WAIT_SECS:-}"
	PROFILE="${PROFILE:-}"
}

template_dir() {
	printf '%s/%s\n' "${TEMPLATES_DIR}" "$1"
}

load_template() {
	_load_name="$1"
	_load_dir=
	_load_dir="$(template_dir "${_load_name}")"
	[ -d "${_load_dir}" ] || die "template not found: ${_load_name}"
	[ -f "${_load_dir}/manifest.env" ] || die "missing ${_load_dir}/manifest.env"

	TEMPLATE_NAME="${_load_name}"
	TEMPLATE_DIR="${_load_dir}"

	# Defaults templates may override (host config.env supplies the baseline).
	TEMPLATE_VCPU_COUNT="${DEFAULT_VCPU_COUNT}"
	TEMPLATE_MEM_MIB="${DEFAULT_MEM_MIB}"
	TEMPLATE_DATA_SIZE_MIB="${DEFAULT_DATA_SIZE_MIB}"
	TEMPLATE_ROOTFS_SIZE_MIB="${BASE_ROOTFS_SIZE_MIB}"
	TEMPLATE_PORT_FORWARDS=""
	TEMPLATE_PACKAGES=""
	TEMPLATE_DESCRIPTION=""
	TEMPLATE_HEALTH_PATH="/"
	TEMPLATE_HEALTH_PORT=""
	TEMPLATE_HEALTH_SCHEME="http"
	TEMPLATE_HEALTH_TLS_VERIFY="0"
	TEMPLATE_TAGS=""
	TEMPLATE_NOTES=""
	TEMPLATE_DATA_HINT="/data"
	TEMPLATE_HEALTH_WAIT_SECS=""

	# Clear keys that manifests may set so defaults stay clean across loads.
	unset DESCRIPTION PORT_FORWARDS PACKAGES HEALTH_PATH HEALTH_PORT HEALTH_SCHEME \
		HEALTH_TLS_VERIFY TAGS NOTES DATA_HINT HEALTH_WAIT_SECS VCPU_COUNT MEM_MIB \
		DATA_SIZE_MIB ROOTFS_SIZE_MIB

	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${_load_dir}/manifest.env"
	set +a

	TEMPLATE_VCPU_COUNT="${VCPU_COUNT:-${TEMPLATE_VCPU_COUNT}}"
	TEMPLATE_MEM_MIB="${MEM_MIB:-${TEMPLATE_MEM_MIB}}"
	TEMPLATE_DATA_SIZE_MIB="${DATA_SIZE_MIB:-${TEMPLATE_DATA_SIZE_MIB}}"
	TEMPLATE_ROOTFS_SIZE_MIB="${ROOTFS_SIZE_MIB:-${TEMPLATE_ROOTFS_SIZE_MIB}}"
	TEMPLATE_PORT_FORWARDS="${PORT_FORWARDS:-${TEMPLATE_PORT_FORWARDS}}"
	TEMPLATE_PACKAGES="${PACKAGES:-${TEMPLATE_PACKAGES}}"
	TEMPLATE_DESCRIPTION="${DESCRIPTION:-${TEMPLATE_DESCRIPTION}}"
	TEMPLATE_HEALTH_PATH="${HEALTH_PATH:-${TEMPLATE_HEALTH_PATH}}"
	TEMPLATE_HEALTH_PORT="${HEALTH_PORT:-${TEMPLATE_HEALTH_PORT}}"
	TEMPLATE_HEALTH_SCHEME="${HEALTH_SCHEME:-${TEMPLATE_HEALTH_SCHEME}}"
	TEMPLATE_HEALTH_TLS_VERIFY="${HEALTH_TLS_VERIFY:-${TEMPLATE_HEALTH_TLS_VERIFY}}"
	TEMPLATE_TAGS="${TAGS:-${TEMPLATE_TAGS}}"
	TEMPLATE_NOTES="${NOTES:-${TEMPLATE_NOTES}}"
	TEMPLATE_DATA_HINT="${DATA_HINT:-${TEMPLATE_DATA_HINT}}"
	TEMPLATE_HEALTH_WAIT_SECS="${HEALTH_WAIT_SECS:-${TEMPLATE_HEALTH_WAIT_SECS}}"
}

each_template() {
	# Print template directory basenames one per line.
	for _et_dir in "${TEMPLATES_DIR}"/*/; do
		[ -d "${_et_dir}" ] || continue
		_et_name="$(basename "${_et_dir}")"
		case "${_et_name}" in
		_*) continue ;;
		esac
		[ -f "${_et_dir}/manifest.env" ] || continue
		printf '%s\n' "${_et_name}"
	done | sort
}

template_has_tag() {
	_th_want="$1"
	_th_tags="$2"
	_th_t=
	_th_old_ifs=${IFS}
	IFS=,
	for _th_t in ${_th_tags}; do
		IFS=${_th_old_ifs}
		_th_t="$(echo "${_th_t}" | tr -d '[:space:]')"
		[ "${_th_t}" = "${_th_want}" ] && return 0
		IFS=,
	done
	IFS=${_th_old_ifs}
	return 1
}

validate_name() {
	_vn_name="$1"
	case "${_vn_name}" in
	*[!a-zA-Z0-9_-]*|'')
		die "invalid name '${_vn_name}' (use letters numbers _ - max 32 chars)"
		;;
	esac
	case "${_vn_name}" in
	[a-zA-Z0-9]*) ;;
	*)
		die "invalid name '${_vn_name}' (use letters numbers _ - max 32 chars)"
		;;
	esac
	if [ ${#_vn_name} -gt 32 ]; then
		die "invalid name '${_vn_name}' (use letters numbers _ - max 32 chars)"
	fi
}

is_running() {
	# True when the pid file points at a live firecracker process.
	# Uses /proc so non-root users can see root-owned guests.
	_ir_pid_file="$1"
	_ir_pid=
	_ir_cmdline=
	[ -f "${_ir_pid_file}" ] || return 1
	_ir_pid="$(tr -d '[:space:]' <"${_ir_pid_file}" 2>/dev/null || true)"
	case "${_ir_pid}" in
	''|*[!0-9]*)
		rm -f "${_ir_pid_file}"
		return 1
		;;
	esac
	if [ ! -r "/proc/${_ir_pid}/cmdline" ]; then
		if [ ! -d "/proc/${_ir_pid}" ]; then
			rm -f "${_ir_pid_file}"
		fi
		return 1
	fi
	_ir_cmdline="$(tr '\0' ' ' <"/proc/${_ir_pid}/cmdline" 2>/dev/null || true)"
	case ${_ir_cmdline} in
	*firecracker*) ;;
	*)
		rm -f "${_ir_pid_file}"
		return 1
		;;
	esac
	return 0
}

next_guest_ip_octet() {
	_ng_used=
	_ng_used="$(find "${INSTANCES_DIR}" -mindepth 2 -maxdepth 2 -name config.env -print0 2>/dev/null \
		| xargs -0 grep -h '^GUEST_IP=' 2>/dev/null \
		| sed -n "s/^GUEST_IP=['\"]\\?${SUBNET_PREFIX}\\.\\([0-9]\\+\\)['\"]\\?$/\\1/p" \
		| sort -n || true)"
	printf '%s\n' "${_ng_used}" | awk 'BEGIN{m=9} NF && $1+0>m{m=$1+0} END{print m+1}'
}

next_guest_cid() {
	_nc_used=
	_nc_used="$(find "${INSTANCES_DIR}" -mindepth 2 -maxdepth 2 -name config.env -print0 2>/dev/null \
		| xargs -0 grep -h '^GUEST_CID=' 2>/dev/null \
		| sed -n 's/^GUEST_CID=['\''"]\?\([0-9]\+\)['\''"]\?$/\1/p' \
		| sort -n || true)"
	printf '%s\n' "${_nc_used}" | awk 'BEGIN{m=2} NF && $1+0>m{m=$1+0} END{print m+1}'
}

mac_from_octet() {
	_mfo_octet="$1"
	printf 'AA:FC:00:00:%02X:%02X\n' $((_mfo_octet / 256)) $((_mfo_octet % 256))
}

ensure_shared() {
	mkdir -p "${SHARED_DIR}" "${INSTANCES_DIR}"
}
