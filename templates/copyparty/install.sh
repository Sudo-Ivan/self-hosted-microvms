#!/bin/sh
# Install copyparty single-file release.
# Upstream: https://github.com/9001/copyparty

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${COPYPARTY_VERSION:-v1.20.18}"
URL="https://github.com/9001/copyparty/releases/download/${VERSION}/copyparty-sfx.py"

mkdir -p /opt/service /data/copyparty/files
download_url "${URL}" /opt/service/copyparty.py
chmod 755 /opt/service/copyparty.py
