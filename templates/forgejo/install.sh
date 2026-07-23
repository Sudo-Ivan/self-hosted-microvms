#!/bin/sh
# Install Forgejo release binary.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${FORGEJO_VERSION:-11.0.1}"
ARCH="$(arch_go)"
URL="https://codeberg.org/forgejo/forgejo/releases/download/v${VERSION}/forgejo-${VERSION}-linux-${ARCH}"

mkdir -p /opt/service /data/forgejo
download_url "${URL}" /opt/service/forgejo
chmod 755 /opt/service/forgejo

if [ ! -f /data/forgejo/app.ini ]; then
	cat >/data/forgejo/app.ini <<'EOF'
APP_NAME = Forgejo
RUN_MODE = prod
RUN_USER = root

[server]
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
DISABLE_SSH = true

[database]
DB_TYPE = sqlite3
PATH = /data/forgejo/forgejo.db

[repository]
ROOT = /data/forgejo/repositories

[data]
PATH = /data/forgejo/data
EOF
fi
