#!/bin/sh
# Start ntfy serve with state on the data volume.

set -eu

mkdir -p /data/ntfy/cache /data/ntfy/attachments
export NTFY_BASE_URL="${NTFY_BASE_URL:-http://127.0.0.1:2586}"
export NTFY_LISTEN_HTTP="${NTFY_LISTEN_HTTP:-:2586}"
export NTFY_CACHE_FILE="${NTFY_CACHE_FILE:-/data/ntfy/cache/cache.db}"
export NTFY_ATTACHMENT_CACHE_DIR="${NTFY_ATTACHMENT_CACHE_DIR:-/data/ntfy/attachments}"
export NTFY_AUTH_FILE="${NTFY_AUTH_FILE:-/data/ntfy/user.db}"
export NTFY_AUTH_DEFAULT_ACCESS="${NTFY_AUTH_DEFAULT_ACCESS:-deny-all}"

exec /opt/service/ntfy serve
