#!/bin/sh
# Install Memos release binary.
# Upstream: https://github.com/usememos/memos

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${MEMOS_VERSION:-v0.29.1}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/usememos/memos/releases/download/${VERSION}/memos_${VER}_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/memos
download_url "${URL}" /tmp/memos.tgz
tar -xzf /tmp/memos.tgz -C /tmp
bin="$(find /tmp -maxdepth 2 -type f -name memos | head -n1)"
[ -n "${bin}" ] || { echo "memos binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/memos
chmod 755 /opt/service/memos
rm -rf /tmp/memos.tgz /tmp/memos /tmp/LICENSE /tmp/README* 2>/dev/null || true
