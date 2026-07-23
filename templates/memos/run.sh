#!/bin/sh
# Start Memos.

set -eu

mkdir -p /data/memos
exec /opt/service/memos \
	--addr 0.0.0.0 \
	--port 5230 \
	--data /data/memos
