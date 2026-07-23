#!/bin/sh
# Install WriteFreely release binary.
# Upstream: https://github.com/writefreely/writefreely

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${WRITEFREELY_VERSION:-v0.17.1}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/writefreely/writefreely/releases/download/${VERSION}/writefreely_${VER}_linux_${ARCH}.tar.gz"

mkdir -p /opt/service /data/writefreely
download_url "${URL}" /tmp/writefreely.tgz
rm -rf /tmp/writefreely-extract
mkdir -p /tmp/writefreely-extract
tar -xzf /tmp/writefreely.tgz -C /tmp/writefreely-extract
bin="$(find /tmp/writefreely-extract -type f -name writefreely | head -n1)"
[ -n "${bin}" ] || { echo "writefreely binary missing" >&2; exit 1; }
cp -f "${bin}" /opt/service/writefreely
chmod 755 /opt/service/writefreely
# Static assets live next to the binary in the release tree.
asset_dir="$(dirname "${bin}")"
if [ -d "${asset_dir}/static" ]; then
	rm -rf /opt/service/writefreely-assets
	mkdir -p /opt/service/writefreely-assets
	cp -a "${asset_dir}/static" "${asset_dir}/templates" "${asset_dir}/pages" /opt/service/writefreely-assets/ 2>/dev/null || true
fi
rm -rf /tmp/writefreely.tgz /tmp/writefreely-extract

if [ ! -f /data/writefreely/config.ini ]; then
	cat >/data/writefreely/config.ini <<'CFG'
[server]
bind              = 0.0.0.0
port              = 8080
templates_parent_dir = /opt/service/writefreely-assets
static_parent_dir    = /opt/service/writefreely-assets
pages_parent_dir     = /opt/service/writefreely-assets

[database]
type     = sqlite3
filename = /data/writefreely/writefreely.db

[app]
site_name = WriteFreely
site_description =
host              = http://127.0.0.1:8080
theme             = write
disable_password_auth = false
single_user       = true
open_registration = false
min_username_len  = 3
federation        = false
public_stats      = false
private           = false
local_timeline    = true
user_invites      = 
CFG
	cd /data/writefreely
	/opt/service/writefreely -c /data/writefreely/config.ini --init-db || true
fi
