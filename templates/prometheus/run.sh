#!/bin/sh
# Start Prometheus.

set -eu

mkdir -p /data/prometheus/data
exec /opt/service/prometheus \
	--config.file=/data/prometheus/prometheus.yml \
	--storage.tsdb.path=/data/prometheus/data \
	--web.listen-address=0.0.0.0:9090 \
	--web.enable-lifecycle
