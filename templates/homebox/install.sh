#!/bin/sh
# Install Homebox release binary.
# Upstream: https://github.com/sysadminsmedia/homebox

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${HOMEBOX_VERSION:-v0.26.2}"
case "$(uname -m)" in
x86_64) ARCH=x86_64 ;;
aarch64|arm64) ARCH=arm64 ;;
*)
	echo "unsupported arch: $(uname -m)" >&2
	exit 1
	;;
esac
URL="https://github.com/sysadminsmedia/homebox/releases/download/${VERSION}/homebox_Linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/homebox
download_url "${URL}" /tmp/homebox.tgz
tar -xzf /tmp/homebox.tgz -C /tmp
bin="$(find /tmp -maxdepth 2 -type f -name homebox | head -n1)"
[ -n "${bin}" ] || { echo "homebox binary missing after extract" >&2; exit 1; }
cp -f "${bin}" /opt/service/homebox
chmod 755 /opt/service/homebox
rm -rf /tmp/homebox.tgz /tmp/homebox /tmp/LICENSE* /tmp/README* 2>/dev/null || true
