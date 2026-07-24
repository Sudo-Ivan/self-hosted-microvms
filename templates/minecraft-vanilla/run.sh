#!/bin/sh
# Run vanilla Minecraft server.

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/minecraft.sh

export PATH="/opt/java/bin:${PATH}"
minecraft_run_jar /opt/service/server.jar
