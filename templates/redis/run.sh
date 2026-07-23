#!/bin/sh
# Start Redis.

set -eu

mkdir -p /data/redis
exec redis-server /data/redis/redis.conf
