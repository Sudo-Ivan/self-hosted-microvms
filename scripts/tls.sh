#!/bin/sh
# Emit host reverse-proxy TLS snippets (compat alias for publish).
#
# Usage:
#   ./scripts/tls.sh <name> --domain app.example.com
#   ./scripts/tls.sh <name> --domain app.example.com --emit caddy
#   ./scripts/tls.sh <name> --domain app.example.com --emit nginx
#   ./scripts/tls.sh <name> --domain app.example.com --write

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "${ROOT}/publish.sh" "$@"
