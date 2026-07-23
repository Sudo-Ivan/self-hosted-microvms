#!/bin/sh
# Install Vikunja full release binary.
# Upstream: https://github.com/go-vikunja/vikunja

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${VIKUNJA_VERSION:-v2.4.0}"
ARCH="$(arch_go)"
URL="https://github.com/go-vikunja/vikunja/releases/download/${VERSION}/vikunja-${VERSION}-linux-${ARCH}-full.zip"

mkdir -p /opt/service /data/vikunja
download_url "${URL}" /tmp/vikunja.zip
unzip -o /tmp/vikunja.zip -d /tmp/vikunja-extract
bin="$(find /tmp/vikunja-extract -type f -name vikunja | head -n1)"
[ -n "${bin}" ] || { echo "vikunja binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/vikunja
chmod 755 /opt/service/vikunja
rm -rf /tmp/vikunja.zip /tmp/vikunja-extract

if [ ! -f /data/vikunja/jwt.secret ]; then
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64 >/data/vikunja/jwt.secret
	chmod 600 /data/vikunja/jwt.secret
fi
