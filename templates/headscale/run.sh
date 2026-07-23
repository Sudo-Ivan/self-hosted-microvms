#!/bin/sh
# Start Headscale.

set -eu

mkdir -p /data/headscale
exec /opt/service/headscale serve -c /data/headscale/config.yaml
