#!/bin/sh
# Install OpenTTD dedicated binary and OpenGFX baseset.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/games.sh

mkdir -p /opt/service /data/openttd
games_ensure_gcompat

echo "resolving OpenTTD"
resolved="$(games_resolve_openttd)"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '2p')"
[ -n "${VERSION}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve OpenTTD" >&2
	exit 1
}
echo "openttd ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/openttd-version

games_download "${URL}" /tmp/openttd.tar.xz
rm -rf /opt/service/openttd
mkdir -p /tmp/openttd-extract /opt/service/openttd
tar -xJf /tmp/openttd.tar.xz -C /tmp/openttd-extract
inner="$(find /tmp/openttd-extract -mindepth 1 -maxdepth 1 -type d | head -n1)"
[ -n "${inner}" ] || {
	echo "openttd extract failed" >&2
	exit 1
}
cp -a "${inner}/." /opt/service/openttd/
rm -rf /tmp/openttd.tar.xz /tmp/openttd-extract
[ -x /opt/service/openttd/openttd ] || {
	echo "openttd binary missing" >&2
	exit 1
}

echo "resolving OpenGFX"
gfx="$(games_resolve_opengfx)"
GFX_VER="$(printf '%s\n' "${gfx}" | sed -n '1p')"
GFX_URL="$(printf '%s\n' "${gfx}" | sed -n '2p')"
games_download "${GFX_URL}" /tmp/opengfx.zip
mkdir -p /data/openttd/baseset
unzip -o /tmp/opengfx.zip -d /tmp/opengfx-extract
# Place .tar or contents into baseset
find /tmp/opengfx-extract -type f \( -name '*.tar' -o -name '*.grf' \) -exec cp -f {} /data/openttd/baseset/ \;
# Some releases are a single opengfx-VERSION.tar inside the zip
if [ ! "$(ls -A /data/openttd/baseset 2>/dev/null)" ]; then
	find /tmp/opengfx-extract -type f -name 'opengfx*.tar' -exec cp -f {} /data/openttd/baseset/ \;
fi
rm -rf /tmp/opengfx.zip /tmp/opengfx-extract
printf '%s\n' "${GFX_VER}" >/opt/service/opengfx-version

if [ ! -f /data/openttd/openttd.cfg ]; then
	cat >/data/openttd/openttd.cfg <<'EOF'
[network]
server_name = OpenTTD mvm
server_port = 3979
max_clients = 16
lan_internet = 0
EOF
fi

chown -R svc:svc /opt/service/openttd /data/openttd 2>/dev/null || true
echo "OpenTTD ${VERSION} ready"
