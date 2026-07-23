#!/bin/sh
# Install Headscale release binary.
# Upstream: https://github.com/juanfont/headscale

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${HEADSCALE_VERSION:-v0.29.2}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/juanfont/headscale/releases/download/${VERSION}/headscale_${VER}_linux_${ARCH}"
CFG_URL="https://raw.githubusercontent.com/juanfont/headscale/${VERSION}/config-example.yaml"

mkdir -p /opt/service /data/headscale
download_url "${URL}" /opt/service/headscale
chmod 755 /opt/service/headscale

if [ ! -f /data/headscale/config.yaml ]; then
	download_url "${CFG_URL}" /data/headscale/config.yaml
	# Point paths at the data volume and listen on all interfaces.
	sed -i \
		-e 's|^server_url:.*|server_url: http://127.0.0.1:8080|' \
		-e 's|^listen_addr:.*|listen_addr: 0.0.0.0:8080|' \
		-e 's|^metrics_listen_addr:.*|metrics_listen_addr: 127.0.0.1:9090|' \
		-e 's|^  # listen_addr:.*|  listen_addr: 127.0.0.1:50443|' \
		-e 's|path: /var/lib/headscale/|path: /data/headscale/|g' \
		-e 's|private_key_path: /var/lib/headscale/|private_key_path: /data/headscale/|g' \
		-e 's|noise:|noise:|' \
		/data/headscale/config.yaml || true
	# Common absolute path rewrites for sqlite/db and keys
	sed -i \
		-e 's|/var/lib/headscale|/data/headscale|g' \
		-e 's|/var/run/headscale|/data/headscale|g' \
		/data/headscale/config.yaml
	mkdir -p /data/headscale
	if [ ! -f /data/headscale/policy.json ]; then
		printf '%s\n' '{}' >/data/headscale/policy.json
	fi
fi
