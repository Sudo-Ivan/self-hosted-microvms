#!/bin/sh
# Build the host secrets CLI into .tools/mvmsec.
#
# Usage:
#   ./scripts/build-mvmsec.sh

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"

require_cmd go
mkdir -p "${REPO_ROOT}/.tools"
info "building mvmsec"
(
	cd "${REPO_ROOT}"
	go build -o "${REPO_ROOT}/.tools/mvmsec" ./cmd/mvmsec/
)
chmod 755 "${REPO_ROOT}/.tools/mvmsec"
echo "wrote ${REPO_ROOT}/.tools/mvmsec"
