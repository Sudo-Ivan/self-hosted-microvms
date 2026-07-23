#!/bin/sh
# Install MeshChatX from PyPI into a local venv.
# Release wheels bundle the web frontend.
# Upstream: https://github.com/Quad4-Software/MeshChatX

set -eu

VERSION="${MESHCHATX_VERSION:-4.7.2}"

mkdir -p /opt/service /data/reticulum /data/meshchatx

python3 -m venv --system-site-packages /opt/service/venv
# shellcheck disable=SC1091
. /opt/service/venv/bin/activate

pip install --upgrade pip wheel setuptools
pip install "reticulum-meshchatx==${VERSION}"

# LXST ships a pyogg fork that misses ctypes aliases on some Python builds.
python /opt/template/patch_lxst_pyogg_ogg_ctypes.py

# On musl, bake the cffi-built filterlib so runtime does not need a compiler.
if ! python /opt/template/bake_lxst_filterlib_musl.py; then
	echo "warning: native LXST filters unavailable (calls audio filters may be limited)" >&2
fi

if [ ! -f /data/reticulum/config ]; then
	cp /opt/template/config.example /data/reticulum/config
fi
