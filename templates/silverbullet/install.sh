#!/bin/sh
# Install SilverBullet server release.
# Upstream: https://github.com/silverbulletmd/silverbullet

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${SILVERBULLET_VERSION:-2.9.0}"
case "$(uname -m)" in
x86_64) ARCH=x86_64 ;;
aarch64|arm64) ARCH=aarch64 ;;
*)
	echo "unsupported arch: $(uname -m)" >&2
	exit 1
	;;
esac
URL="https://github.com/silverbulletmd/silverbullet/releases/download/${VERSION}/silverbullet-server-linux-${ARCH}.zip"

mkdir -p /opt/service /data/silverbullet
download_url "${URL}" /tmp/silverbullet.zip
unzip -o /tmp/silverbullet.zip -d /tmp/silverbullet-extract
bin="$(find /tmp/silverbullet-extract -type f \( -name silverbullet -o -name 'silverbullet-server*' \) | head -n1)"
[ -n "${bin}" ] || { echo "silverbullet binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/silverbullet
chmod 755 /opt/service/silverbullet
rm -rf /tmp/silverbullet.zip /tmp/silverbullet-extract

if [ ! -f /data/silverbullet/auth ]; then
	user="admin"
	pass="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"
	printf '%s:%s\n' "${user}" "${pass}" >/data/silverbullet/auth
	chmod 600 /data/silverbullet/auth
fi
