#!/bin/sh
# Start Gitea.

set -eu

mkdir -p /data/gitea/repositories /data/gitea/data
export GITEA_WORK_DIR=/data/gitea
exec /opt/service/gitea web --config /data/gitea/app.ini
