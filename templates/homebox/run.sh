#!/bin/sh
# Start Homebox.

set -eu

mkdir -p /data/homebox/data
export HBOX_MODE=production
export HBOX_WEB_PORT="${HBOX_WEB_PORT:-7745}"
export HBOX_WEB_HOST=0.0.0.0
export HBOX_STORAGE_DATA=/data/homebox/data
export HBOX_DATABASE_DRIVER=sqlite3
export HBOX_DATABASE_SQLITE_PATH="/data/homebox/data/homebox.db?_pragma=busy_timeout=999&_pragma=journal_mode=WAL&_fk=1"
export HBOX_OPTIONS_ALLOW_REGISTRATION="${HBOX_OPTIONS_ALLOW_REGISTRATION:-true}"
export HBOX_OPTIONS_ALLOW_ANALYTICS=false

exec /opt/service/homebox
