#!/bin/sh
# Run Reticulum-Go with config and storage on the data volume.

set -eu

mkdir -p /data/reticulum-go

if [ ! -f /data/reticulum-go/config ]; then
	cp /opt/template/config.example /data/reticulum-go/config
fi

exec /opt/service/reticulum-go --config /data/reticulum-go
