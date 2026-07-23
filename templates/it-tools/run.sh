#!/bin/sh
# Serve IT-Tools with darkhttpd.

set -eu

exec darkhttpd /opt/service/it-tools --port 8080 --addr 0.0.0.0
