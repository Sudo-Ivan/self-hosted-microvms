#!/bin/sh
# Start PocketBase.

set -eu

mkdir -p /data/pocketbase
exec /opt/service/pocketbase serve \
	--http=0.0.0.0:8090 \
	--dir=/data/pocketbase
