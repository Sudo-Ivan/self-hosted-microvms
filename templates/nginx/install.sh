#!/bin/sh
# Seed nginx config and web root on the data volume.

set -eu

mkdir -p /data/nginx/html /data/nginx/conf.d /data/nginx/logs /run/nginx

if [ ! -f /data/nginx/html/index.html ]; then
	cat >/data/nginx/html/index.html <<'EOF'
<!doctype html>
<html><head><title>nginx microvm</title></head>
<body><h1>nginx microvm is up</h1></body></html>
EOF
fi

if [ ! -f /data/nginx/nginx.conf ]; then
	cat >/data/nginx/nginx.conf <<'EOF'
worker_processes 1;
error_log /data/nginx/logs/error.log warn;
pid /run/nginx/nginx.pid;

events {
	worker_connections 1024;
}

http {
	include /etc/nginx/mime.types;
	default_type application/octet-stream;
	access_log /data/nginx/logs/access.log;
	sendfile on;
	include /data/nginx/conf.d/*.conf;
	server {
		listen 80;
		server_name _;
		root /data/nginx/html;
		index index.html;
	}
}
EOF
fi
