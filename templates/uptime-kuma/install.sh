#!/bin/sh
# Install Uptime Kuma from the upstream release tag.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${UPTIME_KUMA_VERSION:-1.23.16}"
URL="https://github.com/louislam/uptime-kuma/archive/refs/tags/${VERSION}.tar.gz"

mkdir -p /opt/service /data/uptime-kuma
download_url "${URL}" /tmp/uptime-kuma.tgz
mkdir -p /opt/service/uptime-kuma
tar -xzf /tmp/uptime-kuma.tgz -C /opt/service/uptime-kuma --strip-components=1
rm -f /tmp/uptime-kuma.tgz

cd /opt/service/uptime-kuma
npm ci --production
npm run download-dist
