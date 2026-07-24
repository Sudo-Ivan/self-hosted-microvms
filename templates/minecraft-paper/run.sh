#!/bin/sh
# Run Paper Minecraft server.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

export PATH="/opt/java/bin:${PATH}"
# Paper reads plugins from the working directory.
mkdir -p /data/minecraft/plugins
minecraft_run_jar /opt/service/server.jar
