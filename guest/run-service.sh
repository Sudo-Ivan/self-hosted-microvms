#!/bin/sh
# Start the instance service. Delegates to the template run script.

set -eu

TEMPLATE_DIR="/opt/template"

HARDEN=setpriv
HARDEN_USER=svc

if [ -f "${TEMPLATE_DIR}/manifest.env" ]; then
	# shellcheck disable=SC1091
	. "${TEMPLATE_DIR}/manifest.env"
fi

HARDEN="${HARDEN:-setpriv}"
HARDEN_USER="${HARDEN_USER:-svc}"
export HARDEN HARDEN_USER

if [ -f /run/secrets/env ]; then
	# shellcheck disable=SC1091
	set -a
	# shellcheck disable=SC1091
	. /run/secrets/env
	set +a
fi

if [ -x /etc/microvm/prepare-harden.sh ]; then
	/etc/microvm/prepare-harden.sh || echo "prepare-harden failed (continuing)" >&2
fi

if [ -x "${TEMPLATE_DIR}/run.sh" ]; then
	if [ -x /etc/microvm/harden-exec.sh ]; then
		exec /etc/microvm/harden-exec.sh "${TEMPLATE_DIR}/run.sh"
	fi
	exec "${TEMPLATE_DIR}/run.sh"
fi

echo "no template run.sh found" >&2
exec /bin/sh
