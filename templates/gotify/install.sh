#!/bin/sh
# Install Gotify server release.
# Upstream: https://github.com/gotify/server

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${GOTIFY_VERSION:-v3.0.0}"
ARCH="$(arch_go)"
URL="https://github.com/gotify/server/releases/download/${VERSION}/gotify-linux-${ARCH}.zip"

mkdir -p /opt/service /data/gotify
download_url "${URL}" /tmp/gotify.zip
unzip -o /tmp/gotify.zip -d /tmp/gotify-extract
bin="$(find /tmp/gotify-extract -type f -name 'gotify-linux-*' | head -n1)"
[ -n "${bin}" ] || { echo "gotify binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/gotify
chmod 755 /opt/service/gotify
rm -rf /tmp/gotify.zip /tmp/gotify-extract

if [ ! -f /data/gotify/admin.pass ]; then
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 >/data/gotify/admin.pass
	chmod 600 /data/gotify/admin.pass
fi
