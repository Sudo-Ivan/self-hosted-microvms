#!/bin/sh
# CI helper: install POSIX check tools and run check-posix.sh.
#
# Usage:
#   ./scripts/ci-posix.sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${ROOT}"

apt_install() {
	if command -v sudo >/dev/null 2>&1 && [ "$(id -u)" -ne 0 ]; then
		sudo apt-get "$@"
	else
		apt-get "$@"
	fi
}

if command -v apt-get >/dev/null 2>&1; then
	apt_install update
	apt_install install -y shellcheck dash bubblewrap
else
	echo "error: ci-posix.sh expects apt-get (ubuntu-latest CI)" >&2
	exit 1
fi

exec ./scripts/check-posix.sh
