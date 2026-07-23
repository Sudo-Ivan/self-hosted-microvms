#!/bin/sh
# Seed a minimal Caddyfile on the data volume.

set -eu

mkdir -p /data/caddy

if [ ! -f /data/caddy/Caddyfile ]; then
	cat >/data/caddy/Caddyfile <<'EOF'
:80 {
	respond "caddy microvm is up" 200
}
EOF
fi
