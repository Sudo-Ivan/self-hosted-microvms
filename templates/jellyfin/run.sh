#!/bin/sh
# Start Jellyfin.

set -eu

mkdir -p /data/jellyfin/config /data/jellyfin/cache /data/jellyfin/media
FFMPEG="$(command -v ffmpeg || true)"

if [ -n "${FFMPEG}" ]; then
	exec /opt/service/jellyfin-bin \
		--datadir /data/jellyfin/config \
		--cachedir /data/jellyfin/cache \
		--ffmpeg "${FFMPEG}"
fi

exec /opt/service/jellyfin-bin \
	--datadir /data/jellyfin/config \
	--cachedir /data/jellyfin/cache
