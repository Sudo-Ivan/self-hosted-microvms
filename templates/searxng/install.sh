#!/bin/sh
# Install SearXNG from git into a local venv.
# Upstream: https://github.com/searxng/searxng

set -eu

VERSION="${SEARXNG_VERSION:-master}"

mkdir -p /opt/service /data/searxng
rm -rf /opt/service/searxng-src
git clone --depth 1 --branch "${VERSION}" https://github.com/searxng/searxng.git /opt/service/searxng-src

python3 -m venv /opt/service/venv
# shellcheck disable=SC1091
. /opt/service/venv/bin/activate
pip install --upgrade pip setuptools wheel
pip install pyyaml msgspec typing-extensions pybind11
cd /opt/service/searxng-src
pip install --use-pep517 --no-build-isolation -e .

if [ ! -f /data/searxng/settings.yml ]; then
	cp /opt/service/searxng-src/searx/settings.yml /data/searxng/settings.yml
	secret="$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)"
	sed -i "s|ultrasecretkey|${secret}|g" /data/searxng/settings.yml
	sed -i 's|bind_address: "127.0.0.1"|bind_address: "0.0.0.0"|g' /data/searxng/settings.yml
fi
