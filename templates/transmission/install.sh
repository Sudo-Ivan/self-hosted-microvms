#!/bin/sh
# Prepare Transmission config on the data volume.

set -eu

mkdir -p /data/transmission/downloads /data/transmission/incomplete /data/transmission/config

if [ ! -f /data/transmission/config/settings.json ]; then
	cat >/data/transmission/config/settings.json <<'EOF'
{
	"download-dir": "/data/transmission/downloads",
	"incomplete-dir": "/data/transmission/incomplete",
	"incomplete-dir-enabled": true,
	"rpc-authentication-required": false,
	"rpc-bind-address": "0.0.0.0",
	"rpc-enabled": true,
	"rpc-host-whitelist-enabled": false,
	"rpc-whitelist-enabled": false,
	"rpc-port": 9091
}
EOF
fi
