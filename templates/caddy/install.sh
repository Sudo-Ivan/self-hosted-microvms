#!/bin/sh
# Seed a minimal Caddyfile on the data volume with sites/ drop-ins.

set -eu

mkdir -p /data/caddy /data/caddy/sites

if [ ! -f /data/caddy/Caddyfile ]; then
	cat >/data/caddy/Caddyfile <<'EOF'
import /data/caddy/sites/*.caddy

:80 {
	respond "caddy microvm is up" 200
}
EOF
fi
