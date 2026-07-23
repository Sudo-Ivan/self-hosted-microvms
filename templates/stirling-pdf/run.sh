#!/bin/sh
# Start Stirling PDF.

set -eu

mkdir -p /data/stirling-pdf/configs /data/stirling-pdf/logs /data/stirling-pdf/customFiles /data/stirling-pdf/pipeline
export HOME=/data/stirling-pdf
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx768m}"
export SERVER_PORT=8080
export SYSTEM_ROOTURIPATH=/

cd /data/stirling-pdf
exec java -jar /opt/service/stirling-pdf.jar
