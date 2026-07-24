#!/bin/sh
# Run TShock Terraria server.

set -eu

mkdir -p /data/tshock
cd /data/tshock || exit 1
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
if [ -x /opt/service/tshock/TShock.Server ]; then
	exec /opt/service/tshock/TShock.Server -ip 0.0.0.0 -port 7777 -maxplayers 8 -world /data/tshock/world.wld -autocreate 2
fi
if [ -f /opt/service/tshock/TShock.dll ]; then
	# Fallback if only managed entry exists (rare in self-contained builds).
	echo "TShock.Server binary missing; check install layout" >&2
	exit 1
fi
echo "TShock binary not found" >&2
exit 1
