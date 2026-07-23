#!/bin/sh
# Emit host reverse-proxy TLS snippets for an instance.
#
# Usage:
#   ./scripts/tls.sh <name> --domain app.example.com
#   ./scripts/tls.sh <name> --domain app.example.com --emit caddy
#   ./scripts/tls.sh <name> --domain app.example.com --emit nginx
#   ./scripts/tls.sh <name> --domain app.example.com --write

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME=""
DOMAIN=""
EMIT="both"
WRITE=0

usage() {
	sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
	case "$1" in
	-h|--help)
		usage
		exit 0
		;;
	--domain)
		DOMAIN="$2"
		shift 2
		;;
	--emit)
		EMIT="$2"
		shift 2
		;;
	--write)
		WRITE=1
		shift
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		NAME="$1"
		shift
		;;
	esac
done

[ -n "${NAME}" ] && [ -n "${DOMAIN}" ] || die "usage: $0 <name> --domain host.example.com [--emit caddy|nginx|both] [--write]"
load_instance "${NAME}"

host_port="${HEALTH_PORT:-}"
if [ -z "${host_port}" ] && [ -n "${PORT_FORWARDS:-}" ]; then
	first="${PORT_FORWARDS%%,*}"
	first="$(echo "${first}" | tr -d '[:space:]')"
	host_port="${first%%:*}"
fi
[ -n "${host_port}" ] || die "no host port for ${NAME} (set PORT_FORWARDS or HEALTH_PORT)"

backend="127.0.0.1:${host_port}"
out_dir="${INSTANCE_DIR}/tls"
caddy_body="${DOMAIN} {
	reverse_proxy ${backend}
}
"
nginx_body="server {
	listen 443 ssl http2;
	server_name ${DOMAIN};

	ssl_certificate     /etc/ssl/${DOMAIN}.fullchain.pem;
	ssl_certificate_key /etc/ssl/${DOMAIN}.key;

	location / {
		proxy_pass http://${backend};
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
"

write_or_print() {
	kind="$1"
	body="$2"
	path="${out_dir}/${kind}.conf"
	if [ "${WRITE}" = "1" ]; then
		mkdir -p "${out_dir}"
		printf '%s' "${body}" >"${path}"
		echo "wrote ${path}"
	else
		echo "# ${kind} for ${NAME} -> ${backend}"
		printf '%s' "${body}"
		echo
	fi
}

case "${EMIT}" in
caddy)
	write_or_print caddy "${caddy_body}"
	;;
nginx)
	write_or_print nginx "${nginx_body}"
	;;
both)
	write_or_print caddy "${caddy_body}"
	write_or_print nginx "${nginx_body}"
	;;
*)
	die "--emit must be caddy, nginx, or both"
	;;
esac

echo "backend ${backend} (point your host proxy at this)"
