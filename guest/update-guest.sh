#!/bin/sh
# Guest-side package refresh used by scripts/update.sh.

set -eu

if [ -f /etc/apk/repositories ]; then
	apk update
	apk upgrade --no-cache
fi

TEMPLATE_DIR="/opt/template"
if [ -x "${TEMPLATE_DIR}/update.sh" ]; then
	"${TEMPLATE_DIR}/update.sh"
fi

echo "guest update finished"
