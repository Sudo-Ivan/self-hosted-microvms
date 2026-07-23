#!/bin/sh
# Update shared assets or guest packages with automatic pre-update backup.
#
# Usage:
#   ./scripts/update.sh --base
#   ./scripts/update.sh --kernel
#   ./scripts/update.sh <name>
#   ./scripts/update.sh <name> --no-backup
#   ./scripts/update.sh --all-guests

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/backup.sh
. "${LIB_DIR}/backup.sh"
load_config

NO_BACKUP=0
_up_args=
for arg in "$@"; do
	case "${arg}" in
	--no-backup) NO_BACKUP=1 ;;
	*)
		if [ -z "${_up_args}" ]; then
			_up_args=$arg
		else
			_up_args="${_up_args} ${arg}"
		fi
		;;
	esac
done
# shellcheck disable=SC2086
set -- ${_up_args:-}

update_guest() {
	_ug_name="$1"
	_ug_was_running=0
	load_instance "${_ug_name}"

	if is_running "${PID_FILE}"; then
		_ug_was_running=1
	fi

	if [ "${NO_BACKUP}" != "1" ]; then
		info "pre-update backup for ${_ug_name}"
		BACKUP_ROOTFS=1 backup_create "${_ug_name}" "pre-update" >/dev/null
		backup_prune "${_ug_name}" "${BACKUP_KEEP}"
	fi

	info "updating guest packages for ${_ug_name}"
	run_as_root "$(mvm_bin)" stop "${_ug_name}" >/dev/null 2>&1 || true
	run_as_root env MICROVM_MODE=update DETACH=1 "$(mvm_bin)" start "${_ug_name}"

	for _ in $(seq 1 300); do
		if ! is_running "${PID_FILE}"; then
			break
		fi
		sleep 1
	done
	run_as_root "$(mvm_bin)" stop "${_ug_name}" >/dev/null 2>&1 || true

	if [ "${_ug_was_running}" = "1" ]; then
		info "starting ${_ug_name} normally"
		run_as_root "$(mvm_bin)" start "${_ug_name}"
		if ! "${SCRIPTS_DIR}/health.sh" "${_ug_name}" --wait; then
			echo "update finished but health check failed"
			echo "roll back with: ./mvm rollback ${_ug_name}"
			exit 1
		fi
		info "update ok for ${_ug_name}"
	else
		info "update finished (${_ug_name} left stopped)"
	fi
}

case "${1:-}" in
--base)
	"${SCRIPTS_DIR}/build-base.sh"
	;;
--kernel)
	"${SCRIPTS_DIR}/fetch-kernel.sh"
	;;
--all-guests)
	for _ug_dir in "${INSTANCES_DIR}"/*/; do
		[ -d "${_ug_dir}" ] || continue
		_ug_name="$(basename "${_ug_dir}")"
		[ -f "${_ug_dir}/config.env" ] || continue
		update_guest "${_ug_name}"
	done
	;;
"")
	die "usage: $0 --base|--kernel|--all-guests|<name> [--no-backup]"
	;;
*)
	update_guest "$1"
	;;
esac
