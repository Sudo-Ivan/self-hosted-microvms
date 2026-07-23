#!/bin/sh
# Install ntfy server release.
# Upstream: https://github.com/binwiederhier/ntfy

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${NTFY_VERSION:-v2.26.3}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/binwiederhier/ntfy/releases/download/${VERSION}/ntfy_${VER}_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/ntfy
download_url "${URL}" /tmp/ntfy.tgz
tar -xzf /tmp/ntfy.tgz -C /tmp
bin="$(find /tmp -type f -name ntfy | head -n1)"
[ -n "${bin}" ] || { echo "ntfy binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/ntfy
chmod 755 /opt/service/ntfy
rm -rf /tmp/ntfy.tgz /tmp/ntfy_* /tmp/linux_* 2>/dev/null || true
