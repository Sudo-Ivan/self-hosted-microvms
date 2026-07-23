#!/bin/sh
# Configure Redis to use the data volume.

set -eu

mkdir -p /data/redis
cat >/data/redis/redis.conf <<'EOF'
bind 0.0.0.0
port 6379
protected-mode no
dir /data/redis
appendonly yes
daemonize no
EOF
