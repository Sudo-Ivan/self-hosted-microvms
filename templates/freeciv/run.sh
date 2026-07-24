#!/bin/sh
# Run FreeCiv dedicated server.

set -eu

mkdir -p /data/freeciv
cd /data/freeciv || exit 1
exec freeciv-server --bind 0.0.0.0 --port 5556
