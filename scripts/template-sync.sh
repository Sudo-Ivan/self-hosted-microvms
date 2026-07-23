#!/bin/sh
# Sync the host template into an instance rootfs (and optionally restart).
#
# Usage:
#   ./scripts/template-sync.sh <instance>
#   ./scripts/template-sync.sh <instance> --restart
#   ./mvm template sync navi --restart

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/guestfs.sh
. "${LIB_DIR}/guestfs.sh"
load_config

NAME=""
RESTART=0

while [ $# -gt 0 ]; do
	case "$1" in
	--restart)
		RESTART=1
		shift
		;;
	-h|--help)
		sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${NAME}" ]; then
			NAME="$1"
			shift
		else
			die "unexpected argument: $1"
		fi
		;;
	esac
done

[ -n "${NAME}" ] || die "usage: $0 <instance> [--restart]"

if [ "$(id -u)" -ne 0 ]; then
	if [ "${RESTART}" = "1" ]; then
		run_as_root "${SCRIPTS_DIR}/template-sync.sh" "${NAME}" --restart
	else
		run_as_root "${SCRIPTS_DIR}/template-sync.sh" "${NAME}"
	fi
	exit $?
fi

load_instance "${NAME}"

was_running=0
if is_running "${PID_FILE}"; then
	was_running=1
	info "stopping ${NAME} to sync template into rootfs"
	"${SCRIPTS_DIR}/stop.sh" "${NAME}"
fi

guestfs_sync_template

if [ -d "${INSTANCE_DIR}/staging" ] && [ -d "${TEMPLATES_DIR}/${TEMPLATE}" ]; then
	rm -rf "${INSTANCE_DIR}/staging/opt/template"
	mkdir -p "${INSTANCE_DIR}/staging/opt/template"
	cp -a "${TEMPLATES_DIR}/${TEMPLATE}/." "${INSTANCE_DIR}/staging/opt/template/"
	if [ -d "${TEMPLATES_DIR}/_common" ]; then
		mkdir -p "${INSTANCE_DIR}/staging/opt/template/_common"
		cp -a "${TEMPLATES_DIR}/_common/." "${INSTANCE_DIR}/staging/opt/template/_common/"
	fi
fi

if [ "${RESTART}" = "1" ] || [ "${was_running}" = "1" ]; then
	info "starting ${NAME}"
	"${SCRIPTS_DIR}/start.sh" "${NAME}"
	echo "template synced. if install logic changed run: ./mvm update ${NAME}"
else
	echo "template synced into stopped instance ${NAME}"
	echo "start with: $(root_helper) $(mvm_bin) start ${NAME}"
	echo "reinstall/update packages with: ./mvm update ${NAME}"
fi
