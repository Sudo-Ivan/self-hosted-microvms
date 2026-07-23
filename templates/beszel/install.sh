#!/bin/sh
# Install Beszel hub release binary.
# Upstream: https://github.com/henrygd/beszel

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${BESZEL_VERSION:-v0.18.7}"
ARCH="$(arch_go)"
URL="https://github.com/henrygd/beszel/releases/download/${VERSION}/beszel_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/beszel
download_url "${URL}" /tmp/beszel.tgz
tar -xzf /tmp/beszel.tgz -C /tmp
bin="$(find /tmp -maxdepth 2 -type f -name beszel | head -n1)"
[ -n "${bin}" ] || { echo "beszel binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/beszel
chmod 755 /opt/service/beszel
rm -rf /tmp/beszel.tgz /tmp/beszel /tmp/LICENSE* /tmp/README* 2>/dev/null || true
