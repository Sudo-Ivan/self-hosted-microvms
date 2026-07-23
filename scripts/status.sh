#!/bin/sh
# Alias for list/status.
exec "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/list.sh" "$@"
