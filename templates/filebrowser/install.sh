#!/bin/sh
# Install Filebrowser release binary.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${FILEBROWSER_VERSION:-v2.32.0}"
ARCH="$(arch_go)"
URL="https://github.com/filebrowser/filebrowser/releases/download/${VERSION}/linux-${ARCH}-filebrowser.tar.gz"

mkdir -p /opt/service /data/filebrowser/files /data/filebrowser/config
download_url "${URL}" /tmp/filebrowser.tgz
tar -xzf /tmp/filebrowser.tgz -C /opt/service filebrowser
rm -f /tmp/filebrowser.tgz
chmod 755 /opt/service/filebrowser
