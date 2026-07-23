#!/bin/sh
# Install Reticulum-Go release binary.
# Upstream: https://reticulum-go.quad4.io/
# Source: https://github.com/Quad4-Software/Reticulum-Go

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${RETICULUM_GO_VERSION:-v1.0.0}"
ARCH="$(arch_go)"
URL="${RETICULUM_GO_URL:-https://github.com/Quad4-Software/Reticulum-Go/releases/download/${VERSION}/reticulum-go-linux-${ARCH}}"

mkdir -p /opt/service /data/reticulum-go
download_url "${URL}" /opt/service/reticulum-go
chmod 755 /opt/service/reticulum-go

if [ ! -f /data/reticulum-go/config ]; then
	cp /opt/template/config.example /data/reticulum-go/config
fi
