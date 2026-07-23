#!/bin/sh
# Prepare in-guest service hardening (user, packages, data ownership).
# Called from first-boot and before harden-exec.

set -eu

HARDEN="${HARDEN:-setpriv}"
HARDEN_USER="${HARDEN_USER:-svc}"

case "${HARDEN}" in
off|0|no|false|OFF|No|False)
	HARDEN=off
	;;
setpriv|user|caps|"")
	HARDEN=setpriv
	;;
bwrap|bubblewrap)
	HARDEN=bwrap
	;;
*)
	echo "prepare-harden: unknown HARDEN=${HARDEN} (use setpriv, bwrap, or off)" >&2
	exit 1
	;;
esac

if [ "${HARDEN}" = "off" ]; then
	exit 0
fi

ensure_pkgs() {
	need=""
	if ! command -v setpriv >/dev/null 2>&1; then
		need="${need} util-linux"
	fi
	if [ "${HARDEN}" = "bwrap" ] && ! command -v bwrap >/dev/null 2>&1; then
		need="${need} bubblewrap"
	fi
	need="$(printf '%s' "${need}" | sed 's/^ //')"
	[ -n "${need}" ] || return 0
	if [ ! -f /etc/apk/repositories ]; then
		echo "prepare-harden: missing packages:${need}" >&2
		return 1
	fi
	echo "prepare-harden: installing${need}"
	# shellcheck disable=SC2086
	apk add --no-cache ${need}
}

ensure_user() {
	if id -u "${HARDEN_USER}" >/dev/null 2>&1; then
		return 0
	fi
	echo "prepare-harden: creating user ${HARDEN_USER}"
	if command -v adduser >/dev/null 2>&1; then
		adduser -D -H -s /sbin/nologin "${HARDEN_USER}" 2>/dev/null \
			|| adduser -D -s /sbin/nologin "${HARDEN_USER}"
	else
		echo "prepare-harden: adduser missing" >&2
		return 1
	fi
}

fix_data() {
	mkdir -p /data
	# Top-level data dir must be writable by the service user.
	chown "${HARDEN_USER}:${HARDEN_USER}" /data 2>/dev/null || true
	chmod 755 /data 2>/dev/null || true
	# Best effort: reclaim root-owned files on the data filesystem only.
	# -xdev avoids crossing into NFS host shares under /data.
	if command -v find >/dev/null 2>&1; then
		find /data -xdev -user 0 -exec chown "${HARDEN_USER}:${HARDEN_USER}" {} + 2>/dev/null || true
	fi
	# Secrets stay root-owned. They are sourced before drop.
	if [ -d /run/secrets ]; then
		chmod 711 /run/secrets 2>/dev/null || true
	fi
}

ensure_pkgs
ensure_user
fix_data

# Persist resolved mode for harden-exec.
mkdir -p /run/microvm
printf '%s\n' "${HARDEN}" >/run/microvm/harden.mode
printf '%s\n' "${HARDEN_USER}" >/run/microvm/harden.user
echo "prepare-harden: mode=${HARDEN} user=${HARDEN_USER}"
