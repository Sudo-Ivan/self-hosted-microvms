#!/bin/sh
# Install Prometheus release binary.
# Upstream: https://github.com/prometheus/prometheus

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${PROMETHEUS_VERSION:-v3.13.1}"
VER="${VERSION#v}"
ARCH="$(arch_go)"
URL="https://github.com/prometheus/prometheus/releases/download/${VERSION}/prometheus-${VER}.linux-${ARCH}.tar.gz"

mkdir -p /opt/service /data/prometheus
download_url "${URL}" /tmp/prometheus.tgz
rm -rf /tmp/prometheus-extract
mkdir -p /tmp/prometheus-extract
tar -xzf /tmp/prometheus.tgz -C /tmp/prometheus-extract --strip-components=1
cp -f /tmp/prometheus-extract/prometheus /opt/service/prometheus
cp -f /tmp/prometheus-extract/promtool /opt/service/promtool
chmod 755 /opt/service/prometheus /opt/service/promtool
rm -rf /tmp/prometheus.tgz /tmp/prometheus-extract

if [ ! -f /data/prometheus/prometheus.yml ]; then
	cat >/data/prometheus/prometheus.yml <<'CFG'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["127.0.0.1:9090"]
CFG
fi
