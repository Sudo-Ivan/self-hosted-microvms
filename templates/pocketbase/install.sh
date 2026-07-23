#!/bin/sh
# Install PocketBase release binary.
# Upstream: https://github.com/pocketbase/pocketbase

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${POCKETBASE_VERSION:-v0.39.9}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/pocketbase/pocketbase/releases/download/${VERSION}/pocketbase_${VER}_linux_${ARCH}.zip"

mkdir -p /opt/service /data/pocketbase
download_url "${URL}" /tmp/pocketbase.zip
unzip -o /tmp/pocketbase.zip -d /tmp/pocketbase-extract
cp -f /tmp/pocketbase-extract/pocketbase /opt/service/pocketbase
chmod 755 /opt/service/pocketbase
rm -rf /tmp/pocketbase.zip /tmp/pocketbase-extract
