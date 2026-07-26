#!/bin/sh
# Opinionated create/start: instance name defaults to template.
#
# Usage:
#   ./scripts/run.sh <template> [up options...]
#   ./scripts/run.sh [up options...]   (interactive pick)

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

SCRIPTS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

TEMPLATE=""
UP_ARGS=""

while [ $# -gt 0 ]; do
	case "$1" in
	-h | --help)
		cat <<'EOF'
Usage:
  ./mvm run <template> [--profile name] [--share host:guest] [--mem N] [--no-wait] ...
  ./mvm run [--tag=NAME]   (pick template interactively)

Instance name defaults to the template name, or template-2, template-3, ...
Profile uses SUGGESTED_PROFILE from manifest when config DEFAULT_PROFILE is unset.
EOF
		exit 0
		;;
	--share | --profile | --mem | --vcpu | --port)
		if [ $# -lt 2 ]; then
			die "option $1 requires a value"
		fi
		UP_ARGS="${UP_ARGS} $1 $2"
		shift 2
		;;
	--no-wait | --recreate)
		UP_ARGS="${UP_ARGS} $1"
		shift
		;;
	--tag=*)
		if [ -n "${TEMPLATE}" ]; then
			die "unexpected argument: $1"
		fi
		TEMPLATE="$("${SCRIPTS_DIR}/pick.sh" "$1")"
		shift
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${TEMPLATE}" ]; then
			TEMPLATE="$1"
			shift
		else
			die "unexpected argument: $1"
		fi
		;;
	esac
done

if [ -z "${TEMPLATE}" ]; then
	TEMPLATE="$("${SCRIPTS_DIR}/pick.sh")"
fi

load_template "${TEMPLATE}"

INSTANCE="${TEMPLATE}"
_suffix=2
while [ -d "$(instance_dir "${INSTANCE}")" ]; do
	if [ "${INSTANCE}" = "${TEMPLATE}" ]; then
		INSTANCE="${TEMPLATE}-${_suffix}"
	else
		_suffix=$((_suffix + 1))
		INSTANCE="${TEMPLATE}-${_suffix}"
	fi
	if [ "${_suffix}" -gt 99 ]; then
		die "too many instances for template ${TEMPLATE}"
	fi
done

PROFILE_ARG=""
case "${UP_ARGS}" in
*--profile*)
	:
	;;
*)
	if [ -z "${DEFAULT_PROFILE:-}" ] && [ -n "${TEMPLATE_SUGGESTED_PROFILE}" ]; then
		PROFILE_ARG="--profile ${TEMPLATE_SUGGESTED_PROFILE}"
	fi
	;;
esac

# shellcheck disable=SC2086
exec "${SCRIPTS_DIR}/up.sh" "${INSTANCE}" "${TEMPLATE}" ${PROFILE_ARG} ${UP_ARGS}
