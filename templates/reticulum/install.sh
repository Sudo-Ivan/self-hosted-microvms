#!/bin/sh
# Install Reticulum (rns) into a local venv.

set -eu

mkdir -p /opt/service /data/reticulum

python3 -m venv --system-site-packages /opt/service/venv
# shellcheck disable=SC1091
. /opt/service/venv/bin/activate

pip install --upgrade pip wheel

if [ -n "${RNS_VERSION:-}" ]; then
	pip install "rns==${RNS_VERSION}"
else
	pip install rns
fi

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi
