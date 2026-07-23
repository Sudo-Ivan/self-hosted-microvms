#!/bin/sh
# Start MinIO.

set -eu

mkdir -p /data/minio/data
export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD
MINIO_ROOT_USER="$(cat /data/minio/root-user)"
MINIO_ROOT_PASSWORD="$(cat /data/minio/root-password)"
export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD

echo "MinIO console on port 9001"
echo "Credentials are in /data/minio/root-user and /data/minio/root-password on the data volume"

exec /opt/service/minio server /data/minio/data --console-address ":9001" --address ":9000"
