#!/bin/sh
# Keep the guest alive with a shell-friendly sleep loop.

set -eu

echo "alpine-shell guest is idle"
echo "attach host serial logs with scripts/logs.sh"
while true; do
	sleep 3600
done
