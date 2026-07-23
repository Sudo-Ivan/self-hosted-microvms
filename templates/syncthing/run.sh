#!/bin/sh
# Start Syncthing.

set -eu

mkdir -p /data/syncthing/config /data/syncthing/shared
export STNODEFAULTFOLDER=1
export HOME=/data/syncthing
exec syncthing serve \
	--home /data/syncthing/config \
	--gui-address 0.0.0.0:8384 \
	--no-browser \
	--no-upgrade
