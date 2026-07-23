#!/bin/sh
# Install Stirling PDF server JAR.
# Upstream: https://github.com/Stirling-Tools/Stirling-PDF

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="${STIRLING_PDF_VERSION:-v2.14.2}"
URL="https://github.com/Stirling-Tools/Stirling-PDF/releases/download/${VERSION}/Stirling-PDF-server.jar"

mkdir -p /opt/service /data/stirling-pdf
download_url "${URL}" /opt/service/stirling-pdf.jar
