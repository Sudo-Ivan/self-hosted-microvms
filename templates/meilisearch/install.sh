#!/bin/sh
# Install Meilisearch release binary.
# Upstream: https://github.com/meilisearch/meilisearch

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${MEILISEARCH_VERSION:-v1.50.0}"
case "$(uname -m)" in
x86_64) ARCH=amd64 ;;
aarch64|arm64) ARCH=aarch64 ;;
*)
	echo "unsupported arch: $(uname -m)" >&2
	exit 1
	;;
esac
URL="https://github.com/meilisearch/meilisearch/releases/download/${VERSION}/meilisearch-linux-${ARCH}"

mkdir -p /opt/service /data/meilisearch
download_url "${URL}" /opt/service/meilisearch
chmod 755 /opt/service/meilisearch

if [ ! -f /data/meilisearch/master.key ]; then
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 >/data/meilisearch/master.key
	chmod 600 /data/meilisearch/master.key
fi
