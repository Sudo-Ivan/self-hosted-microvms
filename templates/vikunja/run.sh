#!/bin/sh
# Start Vikunja with SQLite.

set -eu

mkdir -p /data/vikunja/files
export VIKUNJA_SERVICE_PUBLICURL="${VIKUNJA_SERVICE_PUBLICURL:-http://127.0.0.1:3456}"
export VIKUNJA_SERVICE_INTERFACE=:3456
export VIKUNJA_SERVICE_JWTSECRET
VIKUNJA_SERVICE_JWTSECRET="$(cat /data/vikunja/jwt.secret)"
export VIKUNJA_SERVICE_JWTSECRET
export VIKUNJA_DATABASE_TYPE=sqlite
export VIKUNJA_DATABASE_PATH=/data/vikunja/vikunja.db
export VIKUNJA_FILES_BASEPATH=/data/vikunja/files

exec /opt/service/vikunja
