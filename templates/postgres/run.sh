#!/bin/sh
# Start PostgreSQL.

set -eu

export PGDATA=/data/postgres/data
mkdir -p /data/postgres/run
export PGHOST=/data/postgres/run

if command -v pg_ctl >/dev/null 2>&1; then
	# Stay in foreground for PID 1 behavior via postgres binary.
	:
fi

# Fix ownership when the postgres user exists.
if id postgres >/dev/null 2>&1; then
	chown -R postgres:postgres /data/postgres
	exec su -s /bin/sh postgres -c "postgres -D ${PGDATA} -k /data/postgres/run"
fi

exec postgres -D "${PGDATA}" -k /data/postgres/run
