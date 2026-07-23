#!/bin/sh
# Start Uptime Kuma.

set -eu

mkdir -p /data/uptime-kuma
export DATA_DIR=/data/uptime-kuma
export UPTIME_KUMA_PORT=3001
export UPTIME_KUMA_HOST=0.0.0.0
cd /opt/service/uptime-kuma
exec node server/server.js
