#!/bin/sh
# Install AdGuard Home release.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${ADGUARDHOME_VERSION:-v0.107.57}"
ARCH="$(arch_go)"
URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${VERSION}/AdGuardHome_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/adguardhome
download_url "${URL}" /tmp/adguardhome.tgz
tar -xzf /tmp/adguardhome.tgz -C /tmp
cp -f /tmp/AdGuardHome/AdGuardHome /opt/service/AdGuardHome
rm -rf /tmp/adguardhome.tgz /tmp/AdGuardHome
chmod 755 /opt/service/AdGuardHome
