#!/bin/sh
# Run SuperTuxKart dedicated server.

set -eu

mkdir -p /data/supertuxkart
cd /data/supertuxkart || exit 1
if command -v supertuxkart >/dev/null 2>&1; then
	exec supertuxkart --server-config=/data/supertuxkart/server_config.xml --network-console
fi
echo "supertuxkart binary not found" >&2
exit 1
