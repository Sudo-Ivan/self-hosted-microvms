#!/bin/sh
# Start Grafana.

set -eu

export GF_PATHS_DATA=/data/grafana/data
export GF_PATHS_LOGS=/data/grafana/logs
export GF_PATHS_PLUGINS=/data/grafana/plugins
export GF_PATHS_PROVISIONING=/data/grafana/provisioning
export GF_SERVER_HTTP_ADDR=0.0.0.0
export GF_SERVER_HTTP_PORT=3000
export GF_SECURITY_ADMIN_USER="${GF_SECURITY_ADMIN_USER:-admin}"
# Set GF_SECURITY_ADMIN_PASSWORD in /data/grafana/admin.env if desired.
if [ -f /data/grafana/admin.env ]; then
	# shellcheck disable=SC1091
	. /data/grafana/admin.env
fi

if command -v grafana-server >/dev/null 2>&1; then
	exec grafana-server --homepath=/usr/share/grafana
fi
if command -v grafana >/dev/null 2>&1; then
	exec grafana server
fi

echo "grafana binary not found" >&2
exit 1
