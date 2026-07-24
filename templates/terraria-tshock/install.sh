#!/bin/sh
# Install TShock Terraria server from GitHub releases.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/games.sh

mkdir -p /opt/service /data/tshock
games_ensure_gcompat

arch="$(games_arch_uname)"
case "${arch}" in
x86_64) pattern='linux-x64-Release\.zip$' ;;
aarch64) pattern='linux-arm64-Release\.zip$' ;;
*)
	echo "unsupported arch for TShock: ${arch}" >&2
	exit 1
	;;
esac

tag="${TSHOCK_VERSION:-latest}"
echo "resolving TShock"
resolved="$(games_github_asset Pryaxis/TShock "${pattern}" "${tag}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '3p')"
echo "tshock ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/tshock-version

games_download "${URL}" /tmp/tshock.zip
rm -rf /opt/service/tshock
mkdir -p /opt/service/tshock
unzip -o /tmp/tshock.zip -d /opt/service/tshock
rm -f /tmp/tshock.zip
# Nested folder in some releases
inner="$(find /opt/service/tshock -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [ -n "${inner}" ] && [ ! -f /opt/service/tshock/TShock.Server ] && [ ! -f /opt/service/tshock/tshock ]; then
	# Flatten one level if binary is nested
	if [ -f "${inner}/TShock.Server" ] || [ -f "${inner}/TShock.dll" ]; then
		cp -a "${inner}/." /opt/service/tshock/
	fi
fi
chmod 755 /opt/service/tshock/TShock.Server 2>/dev/null || true
chmod 755 /opt/service/tshock/tshock 2>/dev/null || true

chown -R svc:svc /opt/service/tshock /data/tshock 2>/dev/null || true
echo "TShock ${VERSION} ready"
