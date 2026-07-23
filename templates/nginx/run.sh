#!/bin/sh
# Start nginx in the foreground.

set -eu

mkdir -p /data/nginx/logs /run/nginx
exec nginx -g 'daemon off;' -c /data/nginx/nginx.conf
