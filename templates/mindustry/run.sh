#!/bin/sh
# Run Mindustry dedicated server.

set -eu

mkdir -p /data/mindustry
cd /data/mindustry || exit 1
export PATH="/opt/java/bin:${PATH}"
xms="${MC_XMS:-512M}"
xmx="${MC_XMX:-1024M}"
echo "starting Mindustry Xms=${xms} Xmx=${xmx}"
exec /opt/java/bin/java -Xms"${xms}" -Xmx"${xmx}" -jar /opt/service/server-release.jar
