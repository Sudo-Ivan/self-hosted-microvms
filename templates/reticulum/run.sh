#!/bin/sh
# Run rnsd with config and identity on the data volume.

set -eu

mkdir -p /data/reticulum

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi

export PATH="/opt/service/venv/bin:${PATH}"
exec rnsd --config /data/reticulum -v
