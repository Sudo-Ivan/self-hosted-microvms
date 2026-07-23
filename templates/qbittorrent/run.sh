#!/bin/sh
# Start qBittorrent-nox in the foreground.

set -eu

mkdir -p /data/qbittorrent/downloads /data/qbittorrent/config
exec qbittorrent-nox --profile=/data/qbittorrent/config --webui-port=8080
