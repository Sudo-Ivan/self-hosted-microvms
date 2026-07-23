#!/bin/sh
# Run NomadNet as a daemon with state on the data volume.

set -eu

mkdir -p /data/reticulum /data/nomadnetwork

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi

export PATH="/opt/service/venv/bin:${PATH}"
exec nomadnet \
	--daemon \
	--console \
	--config /data/nomadnetwork \
	--rnsconfig /data/reticulum
