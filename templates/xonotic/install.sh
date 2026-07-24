#!/bin/sh
# Seed Xonotic server data.

set -eu

mkdir -p /data/xonotic
if [ ! -f /data/xonotic/server.cfg ]; then
	cat >/data/xonotic/server.cfg <<'EOF'
sv_public 0
hostname "Xonotic mvm"
maxplayers 16
port 26000
EOF
fi
chown -R svc:svc /data/xonotic 2>/dev/null || true
echo "xonotic data ready"
