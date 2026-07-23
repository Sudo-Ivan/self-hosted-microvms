#!/bin/sh
# Install Navidrome release binary.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${NAVIDROME_VERSION:-0.54.5}"
ARCH="$(arch_go)"
URL="https://github.com/navidrome/navidrome/releases/download/v${VERSION}/navidrome_${VERSION}_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/navidrome/music /data/navidrome/data
download_url "${URL}" /tmp/navidrome.tgz
tar -xzf /tmp/navidrome.tgz -C /opt/service navidrome
rm -f /tmp/navidrome.tgz
chmod 755 /opt/service/navidrome
