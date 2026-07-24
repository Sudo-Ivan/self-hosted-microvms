#!/bin/sh
# Run Widelands dedicated server.

set -eu

mkdir -p /data/widelands
cd /data/widelands || exit 1
exec widelands --dedicated --port=7396
