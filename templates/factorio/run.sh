#!/bin/sh
# Run Factorio headless server.

set -eu

mkdir -p /data/factorio/saves /data/factorio/mods /data/factorio/config
bin=/opt/service/factorio/bin/x64/factorio
[ -x "${bin}" ] || {
	echo "missing ${bin}" >&2
	exit 1
}

save=""
if [ -n "${FACTORIO_SAVE:-}" ] && [ -f "/data/factorio/saves/${FACTORIO_SAVE}" ]; then
	save="/data/factorio/saves/${FACTORIO_SAVE}"
elif [ -f /data/factorio/saves/default.zip ]; then
	save=/data/factorio/saves/default.zip
else
	# Create a fresh save on first run.
	echo "creating initial Factorio save"
	"${bin}" \
		--create /data/factorio/saves/default.zip \
		--map-gen-settings /opt/service/factorio/data/map-gen-settings.example.json \
		--map-settings /opt/service/factorio/data/map-settings.example.json \
		|| "${bin}" --create /data/factorio/saves/default.zip
	save=/data/factorio/saves/default.zip
fi

echo "starting Factorio with ${save}"
exec "${bin}" \
	--port 34197 \
	--server-settings /data/factorio/config/server-settings.json \
	--start-server "${save}"
