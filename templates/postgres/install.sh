#!/bin/sh
# Initialize PostgreSQL on the data volume when empty.

set -eu

mkdir -p /data/postgres
export PGDATA=/data/postgres/data

if [ ! -f "${PGDATA}/PG_VERSION" ]; then
	mkdir -p "${PGDATA}"
	# Trust auth on the private microvm network. Tighten before public exposure.
	su -s /bin/sh postgres -c "initdb -D ${PGDATA} --auth-local=trust --auth-host=trust" \
		|| initdb -D "${PGDATA}" --auth-local=trust --auth-host=trust --username=postgres
	echo "listen_addresses = '*'" >>"${PGDATA}/postgresql.conf"
	echo "host all all 0.0.0.0/0 trust" >>"${PGDATA}/pg_hba.conf"
fi
