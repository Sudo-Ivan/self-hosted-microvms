#!/bin/sh
# Sync Arma 3 server and mods via Steam CDN, then start the dedicated binary.

set -eu

if [ -f /run/secrets/env ]; then
	# shellcheck disable=SC1091
	set -a
	# shellcheck disable=SC1091
	. /run/secrets/env
	set +a
fi

: "${STEAM_USER:?set STEAM_USER via mvm secrets}"
: "${STEAM_PASSWORD:?set STEAM_PASSWORD via mvm secrets}"

export ARMA_BINARY="${ARMA_BINARY:-./arma3server_x64}"
export ARMA_CONFIG="${ARMA_CONFIG:-main.cfg}"
export ARMA_PARAMS="${ARMA_PARAMS:-}"
export ARMA_PROFILE="${ARMA_PROFILE:-main}"
export ARMA_WORLD="${ARMA_WORLD:-empty}"
export ARMA_LIMITFPS="${ARMA_LIMITFPS:-100}"
export ARMA_CDLC="${ARMA_CDLC:-}"
export PORT="${PORT:-2302}"
export MODS_LOCAL="${MODS_LOCAL:-true}"
export MODS_PRESET="${MODS_PRESET:-}"
export HEADLESS_CLIENTS="${HEADLESS_CLIENTS:-0}"
export HEADLESS_CLIENTS_PROFILE="${HEADLESS_CLIENTS_PROFILE:-\$profile-hc-\$i}"
export SKIP_INSTALL="${SKIP_INSTALL:-false}"
export CLEAR_KEYS="${CLEAR_KEYS:-true}"

export ARMA_DOWNLOAD_MAX_WORKERS="${ARMA_DOWNLOAD_MAX_WORKERS:-4}"
export ARMA_DOWNLOAD_CHUNK_SIZE="${ARMA_DOWNLOAD_CHUNK_SIZE:-4194304}"
export ARMA_DOWNLOAD_PROGRESS_INTERVAL="${ARMA_DOWNLOAD_PROGRESS_INTERVAL:-60}"
export ARMA_CDN_CLIENT_RETRIES="${ARMA_CDN_CLIENT_RETRIES:-3}"
export ARMA_CDN_CLIENT_BASE_DELAY="${ARMA_CDN_CLIENT_BASE_DELAY:-1.5}"
export ARMA_CDN_OP_RETRIES="${ARMA_CDN_OP_RETRIES:-3}"
export ARMA_CDN_OP_BASE_DELAY="${ARMA_CDN_OP_BASE_DELAY:-1.5}"

mkdir -p /data/arma3/cache /data/arma3/presets \
	/data/arma3/server/configs/profiles \
	/data/arma3/server/mpmissions \
	/data/arma3/server/mods \
	/data/arma3/server/servermods \
	/data/arma3/server/keys

if [ ! -L /arma3 ] && [ ! -d /arma3 ]; then
	ln -sfn /data/arma3 /arma3
fi
ln -sfn /data/arma3/server/mods /data/arma3/mods
ln -sfn /data/arma3/server/servermods /data/arma3/servermods

src=/opt/service/arma3server-src
venv=/opt/service/arma3venv
if [ ! -f "${src}/launch.py" ] || [ ! -x "${venv}/bin/python3" ]; then
	echo "arma3 launcher missing, run install/update" >&2
	exit 1
fi

# shellcheck disable=SC1091
. "${venv}/bin/activate"
export PYTHONPATH="${src}${PYTHONPATH:+:${PYTHONPATH}}"
cd /arma3

exec python3 "${src}/launch.py"
