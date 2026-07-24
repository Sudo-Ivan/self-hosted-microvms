#!/bin/sh
# Install Factorio headless from the official dynamic download URL.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/games.sh

mkdir -p /opt/service /data/factorio/saves /data/factorio/mods /data/factorio/config
games_ensure_gcompat

echo "resolving Factorio headless"
resolved="$(games_resolve_factorio)"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '2p')"
[ -n "${VERSION}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve Factorio" >&2
	exit 1
}
echo "factorio ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/factorio-version

games_download "${URL}" /tmp/factorio-headless.tar.xz
rm -rf /opt/service/factorio
mkdir -p /opt/service
tar -xJf /tmp/factorio-headless.tar.xz -C /opt/service
rm -f /tmp/factorio-headless.tar.xz
# Archive extracts to factorio/
[ -x /opt/service/factorio/bin/x64/factorio ] || {
	echo "factorio binary missing after extract" >&2
	exit 1
}

if [ ! -f /data/factorio/config/server-settings.json ]; then
	cat >/data/factorio/config/server-settings.json <<'EOF'
{
  "name": "Factorio mvm",
  "description": "mvm factorio guest",
  "max_players": 8,
  "visibility": { "public": false, "lan": true },
  "game_password": "",
  "require_user_verification": true,
  "max_upload_slots": 5,
  "autosave_interval": 10,
  "autosave_slots": 5,
  "afk_autokick_interval": 0,
  "auto_pause": true
}
EOF
fi

chown -R svc:svc /opt/service/factorio /data/factorio 2>/dev/null || true
echo "Factorio ${VERSION} ready"
