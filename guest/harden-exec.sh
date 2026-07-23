#!/bin/sh
# Drop privileges (and optionally bubblewrap) then exec the service command.
# Usage: harden-exec.sh command [args...]
# Env: HARDEN=setpriv|bwrap|off  HARDEN_USER=svc

set -eu

if [ "$#" -lt 1 ]; then
	echo "usage: harden-exec.sh command [args...]" >&2
	exit 1
fi

HARDEN="${HARDEN:-setpriv}"
HARDEN_USER="${HARDEN_USER:-svc}"

if [ -f /run/microvm/harden.mode ]; then
	HARDEN="$(cat /run/microvm/harden.mode)"
fi
if [ -f /run/microvm/harden.user ]; then
	HARDEN_USER="$(cat /run/microvm/harden.user)"
fi

case "${HARDEN}" in
off|0|no|false|OFF|No|False)
	exec "$@"
	;;
setpriv|user|caps|"")
	HARDEN=setpriv
	;;
bwrap|bubblewrap)
	HARDEN=bwrap
	;;
*)
	echo "harden-exec: unknown HARDEN=${HARDEN}" >&2
	exit 1
	;;
esac

if ! command -v setpriv >/dev/null 2>&1; then
	echo "harden-exec: setpriv missing (install util-linux) falling back to root" >&2
	exec "$@"
fi

if ! id -u "${HARDEN_USER}" >/dev/null 2>&1; then
	echo "harden-exec: user ${HARDEN_USER} missing falling back to root" >&2
	exec "$@"
fi

# Keep NET_BIND_SERVICE so templates can still bind :80/:443/:53.
SETPRIV_ARGS="--reuid=${HARDEN_USER} --regid=${HARDEN_USER} --clear-groups --nnp"
SETPRIV_ARGS="${SETPRIV_ARGS} --inh-caps=-all,+NET_BIND_SERVICE"
SETPRIV_ARGS="${SETPRIV_ARGS} --ambient-caps=+NET_BIND_SERVICE"
SETPRIV_ARGS="${SETPRIV_ARGS} --bounding-set=-all,+NET_BIND_SERVICE"

echo "harden-exec: ${HARDEN} as ${HARDEN_USER}" >&2

if [ "${HARDEN}" = "bwrap" ] && command -v bwrap >/dev/null 2>&1; then
	# Guest init always has /data and /run. Host smoke tests may lack /data.
	BIND_DATA=
	BIND_RUN=
	if [ -d /data ]; then
		BIND_DATA="--bind /data /data"
	fi
	if [ -d /run ]; then
		BIND_RUN="--bind /run /run"
	fi
	# shellcheck disable=SC2086
	exec bwrap --die-with-parent --new-session \
		--ro-bind / / \
		--dev /dev \
		--proc /proc \
		--tmpfs /tmp \
		${BIND_DATA} \
		${BIND_RUN} \
		--chdir / \
		-- setpriv ${SETPRIV_ARGS} -- "$@"
fi

if [ "${HARDEN}" = "bwrap" ]; then
	echo "harden-exec: bwrap missing falling back to setpriv only" >&2
fi

# shellcheck disable=SC2086
exec setpriv ${SETPRIV_ARGS} -- "$@"
