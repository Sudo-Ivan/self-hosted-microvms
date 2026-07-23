#!/bin/sh
# Install NomadNet (and Reticulum) into a local venv.

set -eu

mkdir -p /opt/service /data/reticulum /data/nomadnetwork

python3 -m venv --system-site-packages /opt/service/venv
# shellcheck disable=SC1091
. /opt/service/venv/bin/activate

pip install --upgrade pip wheel

if [ -n "${NOMADNET_VERSION:-}" ]; then
	pip install "nomadnet==${NOMADNET_VERSION}"
else
	pip install nomadnet
fi

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi
