#!/bin/sh
# Install Paper server jar (version/build from Paper Fill v3 API).

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

mkdir -p /opt/service /data/minecraft/plugins

echo "resolving Paper build"
resolved="$(minecraft_resolve_paper "${MC_VERSION:-}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
BUILD="$(printf '%s\n' "${resolved}" | sed -n '2p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '3p')"
[ -n "${VERSION}" ] && [ -n "${BUILD}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve Paper server" >&2
	exit 1
}
echo "paper ${VERSION} build ${BUILD}"
printf '%s\n' "${VERSION}" >/opt/service/mc-version
printf '%s\n' "${BUILD}" >/opt/service/paper-build

JAVA_MAJOR="$(minecraft_java_major "${VERSION}")"
minecraft_install_java "${JAVA_MAJOR}"

minecraft_download "${URL}" /opt/service/server.jar
chmod 644 /opt/service/server.jar
minecraft_prepare_data
chown -R svc:svc /opt/service /opt/java /data/minecraft 2>/dev/null || true
echo "Paper ${VERSION} build ${BUILD} ready"
