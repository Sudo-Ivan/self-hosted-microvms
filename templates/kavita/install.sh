#!/bin/sh
# Install Kavita release (prefer musl on x86_64).
# Upstream: https://github.com/Kareadita/Kavita

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${KAVITA_VERSION:-v0.9.0.2}"
case "$(uname -m)" in
x86_64)
	ASSET=kavita-linux-musl-x64.tar.gz
	;;
aarch64|arm64)
	ASSET=kavita-linux-arm64.tar.gz
	;;
*)
	echo "unsupported arch: $(uname -m)" >&2
	exit 1
	;;
esac
URL="https://github.com/Kareadita/Kavita/releases/download/${VERSION}/${ASSET}"

mkdir -p /opt/service /data/kavita
download_url "${URL}" /tmp/kavita.tgz
rm -rf /opt/service/kavita
mkdir -p /opt/service/kavita
tar -xzf /tmp/kavita.tgz -C /opt/service/kavita --strip-components=1 2>/dev/null \
	|| tar -xzf /tmp/kavita.tgz -C /opt/service/kavita
rm -f /tmp/kavita.tgz
chmod 755 /opt/service/kavita/Kavita 2>/dev/null || chmod 755 /opt/service/kavita/kavita
mkdir -p /data/kavita/config /data/kavita/library
