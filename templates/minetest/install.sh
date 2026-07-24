#!/bin/sh
# Seed Minetest server data dirs.

set -eu

mkdir -p /data/minetest/world /data/minetest/games
if [ ! -f /data/minetest/minetest.conf ]; then
	cat >/data/minetest/minetest.conf <<'EOF'
# Minetest server config. Edit on the data volume.
server_name = Minetest Server
server_description = mvm minetest guest
default_game = minetest
port = 30000
bind_address = 0.0.0.0
creative_mode = false
enable_damage = true
EOF
fi
chown -R svc:svc /data/minetest 2>/dev/null || true
echo "minetest data ready"
