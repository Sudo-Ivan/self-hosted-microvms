#!/bin/sh
# Seed FreeCiv server data.

set -eu

mkdir -p /data/freeciv
chown -R svc:svc /data/freeciv 2>/dev/null || true
echo "freeciv data ready"
