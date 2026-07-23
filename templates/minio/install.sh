#!/bin/sh
# Install MinIO server binary.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

ARCH="$(arch_go)"
# Official release channel. Override MINIO_URL for a dated build.
MINIO_CHANNEL="${MINIO_CHANNEL:-release}"
URL="${MINIO_URL:-https://dl.min.io/server/minio/${MINIO_CHANNEL}/linux-${ARCH}/minio}"

mkdir -p /opt/service /data/minio
download_url "${URL}" /opt/service/minio
chmod 755 /opt/service/minio

# Credentials live only on the data volume and are created on first run if absent.
if [ ! -f /data/minio/root-user ]; then
	# Random local credentials. Replace before exposing the service.
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 >/data/minio/root-user
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 >/data/minio/root-password
	chmod 600 /data/minio/root-user /data/minio/root-password
fi
