#!/bin/sh
# First-boot provisioning. Installs packages and runs template install.sh.

set -eu

TEMPLATE_DIR="/opt/template"
MARKER="/var/lib/microvm/provisioned"

if [ -f "${MARKER}" ]; then
	exit 0
fi

if [ ! -d "${TEMPLATE_DIR}" ]; then
	echo "no template payload at ${TEMPLATE_DIR}" >&2
	exit 1
fi

if [ -f /etc/apk/repositories ]; then
	echo "updating apk indexes"
	apk update
fi

if [ -f "${TEMPLATE_DIR}/manifest.env" ]; then
	# shellcheck disable=SC1091
	. "${TEMPLATE_DIR}/manifest.env"
fi

HARDEN="${HARDEN:-setpriv}"
export HARDEN
export HARDEN_USER="${HARDEN_USER:-svc}"

# Hardening helpers (setpriv / optional bubblewrap).
case "${HARDEN}" in
off|0|no|false|OFF)
	;;
*)
	_harden_pkgs="util-linux"
	case "${HARDEN}" in
	bwrap|bubblewrap) _harden_pkgs="${_harden_pkgs} bubblewrap" ;;
	esac
	if [ -f /etc/apk/repositories ]; then
		echo "installing harden packages: ${_harden_pkgs}"
		# shellcheck disable=SC2086
		apk add --no-cache ${_harden_pkgs} || echo "harden package install failed" >&2
	fi
	;;
esac

if [ -n "${PACKAGES:-}" ]; then
	echo "installing packages: ${PACKAGES}"
	# shellcheck disable=SC2086
	apk add --no-cache ${PACKAGES}
fi

mkdir -p /data /var/lib/microvm

if [ -x /etc/microvm/prepare-harden.sh ]; then
	/etc/microvm/prepare-harden.sh || echo "prepare-harden failed" >&2
fi

if [ -x "${TEMPLATE_DIR}/install.sh" ]; then
	echo "running template install"
	"${TEMPLATE_DIR}/install.sh"
fi

# Re-apply data ownership after install created root-owned files.
if [ -x /etc/microvm/prepare-harden.sh ]; then
	/etc/microvm/prepare-harden.sh || true
fi

echo "provisioning complete"
