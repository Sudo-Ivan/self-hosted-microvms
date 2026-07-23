#!/bin/sh
# Install Jellyfin server from the official Linux archive.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

ARCH="$(arch_go)"
# Channel pin. Override with JELLYFIN_URL for a dated release archive.
JELLYFIN_CHANNEL="${JELLYFIN_CHANNEL:-latest-stable}"

case "${ARCH}" in
amd64) URL="${JELLYFIN_URL:-https://repo.jellyfin.org/files/server/linux/${JELLYFIN_CHANNEL}/amd64/jellyfin_amd64.tar.gz}" ;;
arm64) URL="${JELLYFIN_URL:-https://repo.jellyfin.org/files/server/linux/${JELLYFIN_CHANNEL}/arm64/jellyfin_arm64.tar.gz}" ;;
*)
	echo "unsupported arch for jellyfin: ${ARCH}" >&2
	exit 1
	;;
esac

mkdir -p /opt/service /data/jellyfin/config /data/jellyfin/cache /data/jellyfin/media
download_url "${URL}" /tmp/jellyfin.tgz
mkdir -p /opt/service/jellyfin
tar -xzf /tmp/jellyfin.tgz -C /opt/service/jellyfin --strip-components=1
rm -f /tmp/jellyfin.tgz

if [ -x /opt/service/jellyfin/jellyfin ]; then
	ln -sfn /opt/service/jellyfin/jellyfin /opt/service/jellyfin-bin
elif [ -x /opt/service/jellyfin/jellyfin/jellyfin ]; then
	ln -sfn /opt/service/jellyfin/jellyfin/jellyfin /opt/service/jellyfin-bin
else
	# Find the binary in the extracted tree.
	bin="$(find /opt/service/jellyfin -type f -name jellyfin | head -n1)"
	[ -n "${bin}" ] || { echo "jellyfin binary missing from archive" >&2; exit 1; }
	ln -sfn "${bin}" /opt/service/jellyfin-bin
fi
