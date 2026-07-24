#!/bin/sh
# Run Minetest dedicated server.

set -eu

mkdir -p /data/minetest/world
exec minetestserver \
	--config /data/minetest/minetest.conf \
	--world /data/minetest/world \
	--logfile /data/minetest/server.log
