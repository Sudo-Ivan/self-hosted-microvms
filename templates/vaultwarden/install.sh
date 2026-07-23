#!/bin/sh
# Install Vaultwarden.
# Prefers a binary shipped with the template, otherwise downloads a release asset.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

mkdir -p /opt/service /data/vaultwarden

if [ -x /opt/template/bin/vaultwarden ]; then
	cp -f /opt/template/bin/vaultwarden /opt/service/vaultwarden
	chmod 755 /opt/service/vaultwarden
	exit 0
fi

VERSION="${VAULTWARDEN_VERSION:-1.33.2}"
ARCH="$(arch_uname)"
URL="${VAULTWARDEN_URL:-https://github.com/dani-garcia/vaultwarden/releases/download/${VERSION}/vaultwarden-${ARCH}-unknown-linux-musl.tar.gz}"

download_url "${URL}" /tmp/vaultwarden.tgz
tar -xzf /tmp/vaultwarden.tgz -C /opt/service
rm -f /tmp/vaultwarden.tgz

if [ ! -x /opt/service/vaultwarden ]; then
	bin="$(find /opt/service -type f -name vaultwarden | head -n1)"
	[ -n "${bin}" ] || {
		echo "vaultwarden binary missing after download" >&2
		echo "place a linux musl binary at templates/vaultwarden/bin/vaultwarden and recreate" >&2
		exit 1
	}
	cp -f "${bin}" /opt/service/vaultwarden
fi
chmod 755 /opt/service/vaultwarden
