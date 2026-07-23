#!/bin/sh
# Run Vaultwarden with data on the persistent volume.

set -eu

export DATA_FOLDER="${DATA_FOLDER:-/data/vaultwarden}"
export ROCKET_ADDRESS="${ROCKET_ADDRESS:-0.0.0.0}"
export ROCKET_PORT="${ROCKET_PORT:-80}"
export WEB_VAULT_ENABLED="${WEB_VAULT_ENABLED:-false}"

# Optional admin token is read from the data volume when present.
if [ -f /data/vaultwarden/admin.token ]; then
	ADMIN_TOKEN="$(cat /data/vaultwarden/admin.token)"
	export ADMIN_TOKEN
fi

mkdir -p "${DATA_FOLDER}"
exec /opt/service/vaultwarden
