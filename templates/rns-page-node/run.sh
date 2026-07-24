#!/bin/sh
# Run rns-page-node with state on the data volume.

set -eu

mkdir -p /data/reticulum \
	/data/rns-page-node/pages \
	/data/rns-page-node/files \
	/data/rns-page-node/identity

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/reticulum.config.example /data/reticulum/config
fi

if [ ! -f /data/rns-page-node/config ]; then
	cp /opt/template/config.example /data/rns-page-node/config
fi

export PATH="/opt/service/venv/bin:${PATH}"
export PYTHONUNBUFFERED=1

echo "rns-page-node starting"
echo "  config:    /data/rns-page-node/config"
echo "  reticulum: /data/reticulum"
if grep -q '\[\[0rbit Iceland\]\]' /data/reticulum/config 2>/dev/null; then
	echo "  backbone:  0rbit Iceland present in config"
else
	echo "  backbone:  0rbit Iceland NOT in /data/reticulum/config"
fi

exec rns-page-node \
	--config /data/reticulum \
	/data/rns-page-node/config
