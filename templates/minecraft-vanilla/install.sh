#!/bin/sh
# Install vanilla Minecraft server jar (version from Mojang manifest).

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

mkdir -p /opt/service /data/minecraft

echo "resolving vanilla Minecraft release"
resolved="$(minecraft_resolve_vanilla "${MC_VERSION:-}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '2p')"
[ -n "${VERSION}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve vanilla server" >&2
	exit 1
}
echo "vanilla ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/mc-version

JAVA_MAJOR="$(minecraft_java_major "${VERSION}")"
minecraft_install_java "${JAVA_MAJOR}"

minecraft_download "${URL}" /opt/service/server.jar
chmod 644 /opt/service/server.jar
minecraft_prepare_data
chown -R svc:svc /opt/service /opt/java /data/minecraft 2>/dev/null || true
echo "vanilla Minecraft ${VERSION} ready"
