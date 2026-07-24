#!/bin/sh
# Run Teeworlds dedicated server.

set -eu

mkdir -p /data/teeworlds
cd /opt/service/teeworlds || exit 1
exec ./teeworlds_srv -f /data/teeworlds/server.cfg
