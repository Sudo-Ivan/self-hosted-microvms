#!/bin/sh
# Point Grafana paths at the data volume.

set -eu

mkdir -p /data/grafana/data /data/grafana/logs /data/grafana/plugins /data/grafana/provisioning
