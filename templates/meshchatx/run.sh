#!/bin/sh
# Run MeshChatX headless with its built-in HTTPS (self-signed by default).

set -eu

mkdir -p /data/reticulum /data/meshchatx

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi

if [ -f /data/meshchatx/env ]; then
	# shellcheck disable=SC1091
	set -a
	# shellcheck disable=SC1091
	. /data/meshchatx/env
	set +a
fi

HOST="${MESHCHAT_HOST:-0.0.0.0}"
PORT="${MESHCHAT_PORT:-8000}"

export PATH="/opt/service/venv/bin:${PATH}"
exec meshchatx \
	--headless \
	--host "${HOST}" \
	--port "${PORT}" \
	--storage-dir /data/meshchatx \
	--reticulum-config-dir /data/reticulum
