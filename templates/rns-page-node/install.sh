#!/bin/sh
# Install rns-page-node (and Reticulum) into a local venv.
# Upstream: https://github.com/Quad4-Software/rns-page-node

set -eu

RNS_PAGE_NODE_VERSION="${RNS_PAGE_NODE_VERSION:-1.6.0}"

mkdir -p /opt/service \
	/data/reticulum \
	/data/rns-page-node/pages \
	/data/rns-page-node/files \
	/data/rns-page-node/identity

python3 -m venv --system-site-packages /opt/service/venv
# shellcheck disable=SC1091
. /opt/service/venv/bin/activate

pip install --upgrade pip wheel
pip install "rns-page-node==${RNS_PAGE_NODE_VERSION}"

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/reticulum.config.example /data/reticulum/config
fi

if [ ! -f /data/rns-page-node/config ]; then
	cp /opt/template/config.example /data/rns-page-node/config
fi

if [ ! -f /data/rns-page-node/pages/index.mu ]; then
	cat >/data/rns-page-node/pages/index.mu <<'EOF'
`!`FFFFFFFF`cWelcome

This microVM is running rns-page-node.

Edit pages under /data/rns-page-node/pages and files under /data/rns-page-node/files.
EOF
fi
