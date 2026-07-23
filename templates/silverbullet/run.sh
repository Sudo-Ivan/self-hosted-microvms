#!/bin/sh
# Start SilverBullet.

set -eu

mkdir -p /data/silverbullet/space
export SB_HOSTNAME=0.0.0.0
export SB_PORT=3000
export SB_FOLDER=/data/silverbullet/space
if [ -f /data/silverbullet/auth ]; then
	export SB_USER
	SB_USER="$(tr -d '\n' </data/silverbullet/auth)"
	export SB_USER
	echo "SilverBullet auth: /data/silverbullet/auth"
fi

exec /opt/service/silverbullet
