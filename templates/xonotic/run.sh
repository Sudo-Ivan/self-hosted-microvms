#!/bin/sh
# Run Xonotic dedicated server.

set -eu

mkdir -p /data/xonotic
cd /data/xonotic || exit 1
# Binary name varies by package layout.
if command -v xonotic-dedicated >/dev/null 2>&1; then
	exec xonotic-dedicated +serverconfig /data/xonotic/server.cfg
fi
if command -v xonotic-server >/dev/null 2>&1; then
	exec xonotic-server +serverconfig /data/xonotic/server.cfg
fi
if [ -x /usr/bin/xonotic-dedicated ]; then
	exec /usr/bin/xonotic-dedicated +serverconfig /data/xonotic/server.cfg
fi
echo "xonotic dedicated binary not found" >&2
exit 1
