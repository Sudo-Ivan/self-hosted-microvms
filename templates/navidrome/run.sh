#!/bin/sh
# Start Navidrome.

set -eu

mkdir -p /data/navidrome/data
# Music path is usually a HOST_SHARES mount. Do not create a fake local tree.
if [ ! -d /data/navidrome/music ]; then
	mkdir -p /data/navidrome/music
fi

export ND_MUSICFOLDER=/data/navidrome/music
export ND_DATAFOLDER=/data/navidrome/data
export ND_ADDRESS=0.0.0.0
export ND_PORT=4533

# Fail fast when a share was expected but is empty and not a network fs.
if [ -f /etc/microvm-shares ] && ! grep -q ' /data/navidrome/music ' /proc/mounts 2>/dev/null; then
	echo "music share is not mounted at /data/navidrome/music" >&2
	exit 1
fi

exec /opt/service/navidrome
