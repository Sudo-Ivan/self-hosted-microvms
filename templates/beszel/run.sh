#!/bin/sh
# Start Beszel hub.

set -eu

mkdir -p /data/beszel
exec /opt/service/beszel serve --http 0.0.0.0:8090 --dir /data/beszel
