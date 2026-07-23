#!/bin/sh
# Start SearXNG.

set -eu

export PATH="/opt/service/venv/bin:${PATH}"
export SEARXNG_SETTINGS_PATH=/data/searxng/settings.yml
cd /opt/service/searxng-src
exec python -m searx.webapp
