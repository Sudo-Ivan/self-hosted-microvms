#!/bin/sh
# Start Forgejo.

set -eu

mkdir -p /data/forgejo/repositories /data/forgejo/data
export FORGEJO_WORK_DIR=/data/forgejo
export GITEA_WORK_DIR=/data/forgejo
exec /opt/service/forgejo web --config /data/forgejo/app.ini
