#!/bin/sh
# Prepare qBittorrent-nox config on the data volume.

set -eu

mkdir -p /data/qbittorrent/downloads /data/qbittorrent/config/qBittorrent
CONF=/data/qbittorrent/config/qBittorrent/qBittorrent.conf
if [ ! -f "${CONF}" ]; then
	cat >"${CONF}" <<'CFG'
[LegalNotice]
Accepted=true

[Preferences]
Connection\PortRangeMin=6881
Downloads\SavePath=/data/qbittorrent/downloads
WebUI\Address=*
WebUI\Port=8080
WebUI\LocalHostAuth=false
CFG
fi
