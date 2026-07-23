#!/bin/sh
# One-shot create/start/wait for an instance.
#
# Usage:
#   ./scripts/up.sh <name> <template> [options]
#   ./scripts/up.sh navi navidrome --profile media --share /home/user/Music:/data/navidrome/music:ro
#
# Options:
#   --share host:guest[:ro|rw]   host directory share (repeatable)
#   --profile name               resource profile (small default media db proxy)
#   --mem MiB
#   --vcpu N
#   --port host:guest[:proto]
#   --no-wait
#   --recreate                   destroy existing instance first

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME=""
TEMPLATE=""
SHARE_ENV=""
_UP_NEED_SHARE_DOCTOR=0
MEM=""
VCPU=""
PORTS=""
PROFILE=""
WAIT=1
RECREATE=0

usage() {
	sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
	-h|--help)
		usage
		exit 0
		;;
	--share)
		if [ -n "${SHARE_ENV}" ]; then
			SHARE_ENV="${SHARE_ENV},$2"
		else
			SHARE_ENV="$2"
		fi
		_UP_NEED_SHARE_DOCTOR=1
		shift 2
		;;
	--profile)
		PROFILE="$2"
		shift 2
		;;
	--mem)
		MEM="$2"
		shift 2
		;;
	--vcpu)
		VCPU="$2"
		shift 2
		;;
	--port)
		if [ -n "${PORTS}" ]; then
			PORTS="${PORTS},$2"
		else
			PORTS="$2"
		fi
		shift 2
		;;
	--no-wait)
		WAIT=0
		shift
		;;
	--recreate)
		RECREATE=1
		shift
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${NAME}" ]; then
			NAME="$1"
		elif [ -z "${TEMPLATE}" ]; then
			TEMPLATE="$1"
		else
			die "unexpected argument: $1"
		fi
		shift
		;;
	esac
done

[ -n "${NAME}" ] && [ -n "${TEMPLATE}" ] || die "usage: $0 <name> <template> [--profile name] [--share path:path] [--mem N]"

info "checking host"
if [ "${_UP_NEED_SHARE_DOCTOR}" = "1" ]; then
	"${SCRIPTS_DIR}/doctor.sh" --shares || true
else
	"${SCRIPTS_DIR}/doctor.sh" || true
fi

if [ ! -f "${KERNEL_PATH}" ] || [ ! -d "${SHARED_DIR}/base-staging" ]; then
	info "running setup"
	"${SCRIPTS_DIR}/setup.sh"
fi

if [ "${RECREATE}" = "1" ] && [ -d "$(instance_dir "${NAME}")" ]; then
	info "recreating ${NAME}"
	run_as_root "$(mvm_bin)" destroy "${NAME}" --yes 2>/dev/null \
		|| "${SCRIPTS_DIR}/destroy.sh" "${NAME}" --yes
fi

if [ ! -d "$(instance_dir "${NAME}")" ]; then
	info "creating ${NAME} from ${TEMPLATE}${PROFILE:+ (profile ${PROFILE})}"
	env \
		${SHARE_ENV:+HOST_SHARES="${SHARE_ENV}"} \
		${MEM:+MEM_MIB="${MEM}"} \
		${VCPU:+VCPU_COUNT="${VCPU}"} \
		${PORTS:+PORT_FORWARDS="${PORTS}"} \
		${PROFILE:+PROFILE="${PROFILE}"} \
		"${SCRIPTS_DIR}/create.sh" "${NAME}" "${TEMPLATE}"
else
	if [ -n "${SHARE_ENV}" ]; then
		cfg="$(instance_dir "${NAME}")/config.env"
		if grep -q '^HOST_SHARES=' "${cfg}"; then
			sed -i "s|^HOST_SHARES=.*|HOST_SHARES='${SHARE_ENV}'|" "${cfg}"
		else
			printf "HOST_SHARES='%s'\n" "${SHARE_ENV}" >>"${cfg}"
		fi
		echo "updated HOST_SHARES on existing instance"
	fi
fi

info "starting ${NAME}"
run_as_root "$(mvm_bin)" start "${NAME}"

load_instance "${NAME}"
if [ "${WAIT}" = "1" ]; then
	info "waiting for health"
	if "${SCRIPTS_DIR}/health.sh" "${NAME}" --wait; then
		echo
		echo "${NAME} is up"
		if [ -n "${PORT_FORWARDS:-}" ]; then
			first="${PORT_FORWARDS%%,*}"
			first="$(echo "${first}" | tr -d '[:space:]')"
			host_port="${first%%:*}"
			scheme="${HEALTH_SCHEME:-http}"
			echo "  url:    ${scheme}://127.0.0.1:${host_port}/"
		fi
		echo "  guest:  ${GUEST_IP}"
		echo "  logs:   ./mvm logs ${NAME}"
		echo "  health: ./mvm health ${NAME}"
		echo "  stop:   sudo ./mvm stop ${NAME}"
	else
		echo
		echo "${NAME} started but health checks timed out"
		echo "  logs: ./mvm logs ${NAME}"
		exit 1
	fi
else
	echo "${NAME} start issued"
fi
