#!/bin/sh
# Start Transmission daemon in the foreground.

set -eu

mkdir -p /data/transmission/downloads /data/transmission/incomplete /data/transmission/config
exec transmission-daemon --foreground --config-dir /data/transmission/config
