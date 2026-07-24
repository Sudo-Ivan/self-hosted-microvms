#!/bin/sh
# Run OpenTTD dedicated server.

set -eu

mkdir -p /data/openttd/baseset /data/openttd/save
export PATH="/opt/service/openttd:${PATH}"
cd /data/openttd || exit 1
exec /opt/service/openttd/openttd -D -c /data/openttd/openttd.cfg
