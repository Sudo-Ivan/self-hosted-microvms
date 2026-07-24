#!/bin/sh
# Install Teeworlds dedicated server from GitHub releases.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/games.sh

mkdir -p /opt/service /data/teeworlds
games_ensure_gcompat

arch="$(games_arch_uname)"
case "${arch}" in
x86_64) pattern='linux_x86_64\.tar\.gz$' ;;
*)
	echo "teeworlds template currently ships x86_64 upstream builds only (got ${arch})" >&2
	exit 1
	;;
esac

tag="${TEEWORLDS_VERSION:-latest}"
echo "resolving Teeworlds"
resolved="$(games_github_asset teeworlds/teeworlds "${pattern}" "${tag}")"
VERSION="$(printf '%s\n' "${resolved}" | sed -n '1p')"
URL="$(printf '%s\n' "${resolved}" | sed -n '3p')"
echo "teeworlds ${VERSION}"
printf '%s\n' "${VERSION}" >/opt/service/teeworlds-version

games_download "${URL}" /tmp/teeworlds.tgz
rm -rf /opt/service/teeworlds
mkdir -p /tmp/teeworlds-extract /opt/service/teeworlds
tar -xzf /tmp/teeworlds.tgz -C /tmp/teeworlds-extract
inner="$(find /tmp/teeworlds-extract -mindepth 1 -maxdepth 1 -type d | head -n1)"
if [ -n "${inner}" ]; then
	cp -a "${inner}/." /opt/service/teeworlds/
else
	cp -a /tmp/teeworlds-extract/. /opt/service/teeworlds/
fi
rm -rf /tmp/teeworlds.tgz /tmp/teeworlds-extract
chmod 755 /opt/service/teeworlds/teeworlds_srv 2>/dev/null || true
[ -x /opt/service/teeworlds/teeworlds_srv ] || {
	echo "teeworlds_srv missing" >&2
	exit 1
}

if [ ! -f /data/teeworlds/server.cfg ]; then
	cat >/data/teeworlds/server.cfg <<'EOF'
sv_name Teeworlds mvm
sv_max_clients 12
sv_port 8303
sv_gametype ctf
EOF
fi

chown -R svc:svc /opt/service/teeworlds /data/teeworlds 2>/dev/null || true
echo "Teeworlds ${VERSION} ready"
