#!/bin/sh
# Start Kavita.

set -eu

mkdir -p /data/kavita/config /data/kavita/library
cd /opt/service/kavita
export KAVITA_CONFIG_DIRECTORY=/data/kavita/config
export ASPNETCORE_URLS=http://0.0.0.0:5000
if [ -x ./Kavita ]; then
	exec ./Kavita
fi
exec ./kavita
