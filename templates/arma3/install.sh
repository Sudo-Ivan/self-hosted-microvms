#!/bin/sh
# Install Arma 3 server launcher (Steam CDN sync, workshop presets).
# Upstream: https://github.com/frederik-hoeft/Arma3Server (BrettMayson/Arma3Server PR #97)

set -eu

ARMA3SERVER_VERSION=16606741a70e83f09ba084220faf7ff19dc87e2e
ARMA3SERVER_REPO="${ARMA3SERVER_REPO:-frederik-hoeft/Arma3Server}"
ARMA3SERVER_REF="${ARMA3SERVER_VERSION}"

# shellcheck disable=SC1091
. /opt/template/_common/games.sh

games_ensure_gcompat

mkdir -p /opt/service /data/arma3/cache /data/arma3/presets \
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
rm -rf "${src}"
git clone --filter=blob:none --no-checkout "https://github.com/${ARMA3SERVER_REPO}.git" "${src}"
git -C "${src}" fetch --depth 1 origin "${ARMA3SERVER_REF}"
git -C "${src}" checkout --detach FETCH_HEAD
printf '%s\n' "$(git -C "${src}" rev-parse HEAD)" >/opt/service/arma3server-ref

python3 -m venv /opt/service/arma3venv
# shellcheck disable=SC1091
. /opt/service/arma3venv/bin/activate
pip install --upgrade pip wheel setuptools
pip install -U zstandard
pip install "steam[client] @ git+https://github.com/brettmayson/valvepythonsteam"

if [ ! -f /data/arma3/server/configs/main.cfg ]; then
	cp "${src}/configs/main.cfg" /data/arma3/server/configs/main.cfg
fi

chown -R svc:svc /data/arma3 2>/dev/null || true
echo "Arma 3 launcher ${ARMA3SERVER_REF} ready"
