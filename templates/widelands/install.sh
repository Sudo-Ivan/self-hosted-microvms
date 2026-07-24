#!/bin/sh
# Seed Widelands server data.

set -eu

mkdir -p /data/widelands
chown -R svc:svc /data/widelands 2>/dev/null || true
echo "widelands data ready"
