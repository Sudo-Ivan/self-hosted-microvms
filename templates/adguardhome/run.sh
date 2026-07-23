#!/bin/sh
# Start AdGuard Home.

set -eu

mkdir -p /data/adguardhome/work /data/adguardhome/conf
exec /opt/service/AdGuardHome \
	-w /data/adguardhome/work \
	-c /data/adguardhome/conf/AdGuardHome.yaml \
	--no-check-update
