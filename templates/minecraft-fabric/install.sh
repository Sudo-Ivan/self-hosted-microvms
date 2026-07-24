#!/bin/sh
# Install Fabric server jar (versions from Fabric meta API).

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

mkdir -p /opt/service /data/minecraft/mods

echo "resolving Fabric server"
resolved="$(minecraft_resolve_fabric "${MC_VERSION:-}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
LOADER="$(printf '%s\n' "${resolved}" | sed -n '2p')"
INSTALLER="$(printf '%s\n' "${resolved}" | sed -n '3p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '4p')"
[ -n "${VERSION}" ] && [ -n "${LOADER}" ] && [ -n "${INSTALLER}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve Fabric server" >&2
	exit 1
}
echo "fabric game=${VERSION} loader=${LOADER} installer=${INSTALLER}"
printf '%s\n' "${VERSION}" >/opt/service/mc-version
printf '%s\n' "${LOADER}" >/opt/service/fabric-loader
printf '%s\n' "${INSTALLER}" >/opt/service/fabric-installer

JAVA_MAJOR="$(minecraft_java_major "${VERSION}")"
minecraft_install_java "${JAVA_MAJOR}"

minecraft_download "${URL}" /opt/service/server.jar
chmod 644 /opt/service/server.jar
minecraft_prepare_data
chown -R svc:svc /opt/service /opt/java /data/minecraft 2>/dev/null || true
echo "Fabric ${VERSION} ready"
