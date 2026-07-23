#!/bin/sh
# Install IT-Tools static web release.
# Upstream: https://github.com/CorentinTh/it-tools

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${IT_TOOLS_VERSION:-v2024.10.22-7ca5933}"
VER="${VERSION#v}"
URL="https://github.com/CorentinTh/it-tools/releases/download/${VERSION}/it-tools-${VER}.zip"

mkdir -p /opt/service/it-tools /data/it-tools
download_url "${URL}" /tmp/it-tools.zip
unzip -o /tmp/it-tools.zip -d /tmp/it-tools-extract
# Release zip usually contains the built SPA at the root or in a dist folder.
if [ -f /tmp/it-tools-extract/index.html ]; then
	cp -a /tmp/it-tools-extract/. /opt/service/it-tools/
elif [ -d /tmp/it-tools-extract/dist ]; then
	cp -a /tmp/it-tools-extract/dist/. /opt/service/it-tools/
else
	inner="$(find /tmp/it-tools-extract -type f -name index.html | head -n1)"
	[ -n "${inner}" ] || { echo "it-tools index.html missing" >&2; exit 1; }
	cp -a "$(dirname "${inner}")/." /opt/service/it-tools/
fi
rm -rf /tmp/it-tools.zip /tmp/it-tools-extract
