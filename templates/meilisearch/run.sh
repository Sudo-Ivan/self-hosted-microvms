#!/bin/sh
# Start Meilisearch.

set -eu

mkdir -p /data/meilisearch/data
export MEILI_HTTP_ADDR=0.0.0.0:7700
export MEILI_DB_PATH=/data/meilisearch/data
export MEILI_ENV=production
export MEILI_NO_ANALYTICS=true
export MEILI_MASTER_KEY
MEILI_MASTER_KEY="$(cat /data/meilisearch/master.key)"
export MEILI_MASTER_KEY

echo "Meilisearch master key: /data/meilisearch/master.key"

exec /opt/service/meilisearch
