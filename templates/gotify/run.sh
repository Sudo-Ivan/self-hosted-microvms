#!/bin/sh
# Start Gotify with SQLite on the data volume.

set -eu

mkdir -p /data/gotify
export GOTIFY_SERVER_PORT="${GOTIFY_SERVER_PORT:-80}"
export GOTIFY_DATABASE_DIALECT=sqlite3
export GOTIFY_DATABASE_CONNECTION=/data/gotify/gotify.db
export GOTIFY_DEFAULTUSER_NAME="${GOTIFY_DEFAULTUSER_NAME:-admin}"
export GOTIFY_DEFAULTUSER_PASS
GOTIFY_DEFAULTUSER_PASS="$(cat /data/gotify/admin.pass)"
export GOTIFY_DEFAULTUSER_PASS

echo "Gotify default user: ${GOTIFY_DEFAULTUSER_NAME}"
echo "Password file: /data/gotify/admin.pass"

exec /opt/service/gotify serve
