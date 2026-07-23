#!/bin/sh
# Start Filebrowser.

set -eu

mkdir -p /data/filebrowser/files /data/filebrowser/config
DB=/data/filebrowser/config/filebrowser.db
ROOT=/data/filebrowser/files

if [ ! -f "${DB}" ]; then
	/opt/service/filebrowser config init --database "${DB}"
	/opt/service/filebrowser config set --database "${DB}" --address 0.0.0.0 --port 80 --root "${ROOT}"
	# Default login is admin. Password is printed once on first init by filebrowser.
	/opt/service/filebrowser users add admin admin --database "${DB}" --perm.admin || true
fi

exec /opt/service/filebrowser --database "${DB}"
