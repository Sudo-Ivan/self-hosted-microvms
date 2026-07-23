#!/bin/sh
# Prepare Syncthing home on the data volume.

set -eu

mkdir -p /data/syncthing /data/syncthing/config /data/syncthing/shared
