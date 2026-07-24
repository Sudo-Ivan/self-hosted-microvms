#!/bin/sh
# Install Mindustry dedicated server jar from GitHub latest release.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/games.sh
# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

mkdir -p /opt/service /data/mindustry

echo "resolving Mindustry server jar"
tag="${MINDUSTRY_VERSION:-latest}"
resolved="$(games_github_asset Anuken/Mindustry '^server-release\.jar$' "${tag}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '3p')"
[ -n "${VERSION}" ] && [ -n "${URL}" ] || {
	echo "failed to resolve Mindustry" >&2
	exit 1
}
echo "mindustry ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/mindustry-version

minecraft_install_java 21
games_download "${URL}" /opt/service/server-release.jar
chmod 644 /opt/service/server-release.jar
chown -R svc:svc /opt/service /opt/java /data/mindustry 2>/dev/null || true
echo "Mindustry ${VERSION} ready"
