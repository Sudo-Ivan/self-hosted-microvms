#!/bin/sh
# Start copyparty.

set -eu

mkdir -p /data/copyparty/files
exec python3 /opt/service/copyparty.py \
	-p 3923 \
	--no-banish \
	-v /data/copyparty/files::rw
