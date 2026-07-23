#!/bin/sh
# Start Caddy.

set -eu

mkdir -p /data/caddy /data/caddy/data /data/caddy/config
export XDG_DATA_HOME=/data/caddy/data
export XDG_CONFIG_HOME=/data/caddy/config
exec caddy run --config /data/caddy/Caddyfile --adapter caddyfile
