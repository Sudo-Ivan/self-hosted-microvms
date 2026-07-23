#!/bin/sh
# Install Gitea release binary.
# Upstream: https://github.com/go-gitea/gitea

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${GITEA_VERSION:-1.27.0}"
ARCH="$(arch_go)"
URL="https://github.com/go-gitea/gitea/releases/download/v${VERSION}/gitea-${VERSION}-linux-${ARCH}"

mkdir -p /opt/service /data/gitea
download_url "${URL}" /opt/service/gitea
chmod 755 /opt/service/gitea

if [ ! -f /data/gitea/app.ini ]; then
	cat >/data/gitea/app.ini <<'CFG'
APP_NAME = Gitea
RUN_MODE = prod
RUN_USER = root

[server]
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
DISABLE_SSH = true

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[repository]
ROOT = /data/gitea/repositories

[data]
PATH = /data/gitea/data
CFG
fi
