#!/bin/sh
# Start WriteFreely.

set -eu

mkdir -p /data/writefreely
cd /data/writefreely
exec /opt/service/writefreely -c /data/writefreely/config.ini
