#!/bin/sh
# Publish an instance behind a host reverse proxy or a proxy microVM.
#
# Usage:
#   ./scripts/publish.sh <name> --domain app.example.com
#   ./scripts/publish.sh <name> --domain app.example.com --emit caddy --write
#   ./scripts/publish.sh <name> --domain app.example.com --via edge [--restart-via]
#   ./mvm publish app --domain git.example.com --via edge --restart-via

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
# shellcheck source=../lib/guestfs.sh
. "${LIB_DIR}/guestfs.sh"
# shellcheck source=../lib/network.sh
. "${LIB_DIR}/network.sh"
load_config

NAME=""
DOMAIN=""
EMIT="both"
WRITE=0
VIA=""
RESTART_VIA=0

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
	--via)
		VIA="$2"
		shift 2
		;;
	--restart-via)
		RESTART_VIA=1
		shift
		;;
	-*)
		die "unknown option: $1"
		;;
	*)
		if [ -z "${NAME}" ]; then
			NAME="$1"
			shift
		else
			die "unexpected argument: $1"
		fi
		;;
	esac
done

if [ -z "${NAME}" ] || [ -z "${DOMAIN}" ]; then
	die "usage: $0 <name> --domain host.example.com [--via proxy] [--emit caddy|nginx|both] [--write] [--restart-via]"
fi
validate_name "${NAME}"
load_instance "${NAME}"

APP_GUEST_IP="${GUEST_IP}"
APP_PORT_FORWARDS="${PORT_FORWARDS:-}"
APP_HEALTH_PORT="${HEALTH_PORT:-}"
APP_DIR="${INSTANCE_DIR}"

first_forward_ports() {
	# Sets HOST_PORT and GUEST_PORT from PORT_FORWARDS / HEALTH_PORT.
	_pf="$1"
	_hp="$2"
	HOST_PORT=""
	GUEST_PORT=""
	if [ -n "${_pf}" ]; then
		_first="${_pf%%,*}"
		_first="$(echo "${_first}" | tr -d '[:space:]')"
		parse_forward "${_first}"
		# parse_forward sets HOST_PORT GUEST_PORT PROTO
		return 0
	fi
	if [ -n "${_hp}" ]; then
		HOST_PORT="${_hp}"
		GUEST_PORT="${_hp}"
		return 0
	fi
	return 1
}

first_forward_ports "${APP_PORT_FORWARDS}" "${APP_HEALTH_PORT}" \
	|| die "no host/guest port for ${NAME} (set PORT_FORWARDS or HEALTH_PORT)"

APP_HOST_PORT="${HOST_PORT}"
APP_GUEST_PORT="${GUEST_PORT}"

caddy_site_body() {
	_up="$1"
	printf '%s {\n\treverse_proxy %s\n}\n' "${DOMAIN}" "${_up}"
}

nginx_site_body() {
	_up="$1"
	cat <<EOF
server {
	listen 443 ssl http2;
	server_name ${DOMAIN};

	ssl_certificate     /etc/ssl/${DOMAIN}.fullchain.pem;
	ssl_certificate_key /etc/ssl/${DOMAIN}.key;

	location / {
		proxy_pass http://${_up};
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
EOF
}

write_or_print() {
	kind="$1"
	body="$2"
	path="${APP_DIR}/tls/${kind}.conf"
	if [ "${WRITE}" = "1" ]; then
		mkdir -p "${APP_DIR}/tls"
		printf '%s' "${body}" >"${path}"
		echo "wrote ${path}"
	else
		echo "# ${kind} for ${NAME} -> backend"
		printf '%s' "${body}"
		echo
	fi
}

firewall_add_peer() {
	_fw="$1"
	_peer="$2"
	[ -f "${_fw}" ] || {
		cp -f "${REPO_ROOT}/argus/firewall.example.env" "${_fw}"
	}
	_cur=
	_cur="$(grep '^ALLOW_PEERS=' "${_fw}" 2>/dev/null | sed 's/^ALLOW_PEERS=//' | tr -d \"\' || true)"
	case ",${_cur}," in
	*",${_peer},"*)
		return 0
		;;
	esac
	if [ -z "${_cur}" ]; then
		_new="${_peer}"
	else
		_new="${_cur},${_peer}"
	fi
	if grep -q '^ALLOW_PEERS=' "${_fw}"; then
		sed -i "s|^ALLOW_PEERS=.*|ALLOW_PEERS=${_new}|" "${_fw}"
	else
		printf 'ALLOW_PEERS=%s\n' "${_new}" >>"${_fw}"
	fi
	echo "updated ${_fw} ALLOW_PEERS=${_new}"
}

ensure_caddy_import() {
	_mnt="$1"
	_cf="${_mnt}/data/caddy/Caddyfile"
	mkdir -p "${_mnt}/data/caddy/sites"
	if [ ! -f "${_cf}" ]; then
		cat >"${_cf}" <<'EOF'
import /data/caddy/sites/*.caddy

:80 {
	respond "caddy microvm is up" 200
}
EOF
		return 0
	fi
	if ! grep -q 'sites/\*\.caddy' "${_cf}"; then
		tmp="$(mktemp)"
		printf 'import /data/caddy/sites/*.caddy\n\n' >"${tmp}"
		cat "${_cf}" >>"${tmp}"
		mv -f "${tmp}" "${_cf}"
		echo "added sites import to Caddyfile"
	fi
}

ensure_nginx_confd() {
	_mnt="$1"
	_nf="${_mnt}/data/nginx/nginx.conf"
	mkdir -p "${_mnt}/data/nginx/conf.d" "${_mnt}/data/nginx/logs" "${_mnt}/data/nginx/html"
	if [ ! -f "${_nf}" ]; then
		cat >"${_nf}" <<'EOF'
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
		return 0
	fi
	if ! grep -q 'conf.d/\*\.conf' "${_nf}"; then
		tmp="$(mktemp)"
		awk '
			/^[[:space:]]*http[[:space:]]*\{/ { print; print "\tinclude /data/nginx/conf.d/*.conf;"; next }
			{ print }
		' "${_nf}" >"${tmp}"
		mv -f "${tmp}" "${_nf}"
		echo "added conf.d include to nginx.conf"
	fi
}

if [ -z "${VIA}" ]; then
	backend="127.0.0.1:${APP_HOST_PORT}"
	caddy_body="$(caddy_site_body "${backend}")"
	nginx_body="$(nginx_site_body "${backend}")"
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
	exit 0
fi

# --via <proxy-instance>: inject site into that guest data volume.
validate_name "${VIA}"
[ "${VIA}" != "${NAME}" ] || die "--via cannot be the same instance as ${NAME}"

# Capture app backend on the bridge before loading the proxy instance.
UPSTREAM="${APP_GUEST_IP}:${APP_GUEST_PORT}"

load_instance "${VIA}"
VIA_TEMPLATE="${TEMPLATE:-}"
VIA_DIR="${INSTANCE_DIR}"
VIA_PID="${PID_FILE}"
VIA_NAME="${INSTANCE_NAME}"

case "${VIA_TEMPLATE}" in
caddy|nginx) ;;
*)
	die "--via ${VIA} template is '${VIA_TEMPLATE:-unknown}' (need caddy or nginx)"
	;;
esac

# Rebuild argv for ensure_root (option parsing already consumed "$@").
set -- "${NAME}" --domain "${DOMAIN}" --via "${VIA}" --emit "${EMIT}"
if [ "${WRITE}" = "1" ]; then
	set -- "$@" --write
fi
if [ "${RESTART_VIA}" = "1" ]; then
	set -- "$@" --restart-via
fi
ensure_root "$@"

via_was_running=0
if is_running "${VIA_PID}"; then
	via_was_running=1
	info "stopping ${VIA_NAME} to write site config into data volume"
	"${SCRIPTS_DIR}/stop.sh" "${VIA_NAME}"
fi

# load_instance for VIA already set DATA_PATH / INSTANCE_DIR
guestfs_mount_data
mnt="${GUESTFS_MNT}"
trap 'guestfs_umount' EXIT

case "${VIA_TEMPLATE}" in
caddy)
	ensure_caddy_import "${mnt}"
	site_path="${mnt}/data/caddy/sites/${NAME}.caddy"
	caddy_site_body "${UPSTREAM}" >"${site_path}"
	echo "wrote ${VIA_NAME}:/data/caddy/sites/${NAME}.caddy -> ${UPSTREAM}"
	;;
nginx)
	ensure_nginx_confd "${mnt}"
	site_path="${mnt}/data/nginx/conf.d/${NAME}.conf"
	# Bridge-side nginx often terminates TLS on the proxy guest itself.
	cat >"${site_path}" <<EOF
server {
	listen 80;
	server_name ${DOMAIN};

	location / {
		proxy_pass http://${UPSTREAM};
		proxy_set_header Host \$host;
		proxy_set_header X-Real-IP \$remote_addr;
		proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header X-Forwarded-Proto \$scheme;
	}
}
EOF
	echo "wrote ${VIA_NAME}:/data/nginx/conf.d/${NAME}.conf -> ${UPSTREAM}"
	;;
esac

guestfs_umount
trap - EXIT

firewall_add_peer "${VIA_DIR}/firewall.env" "${NAME}"

if [ "${via_was_running}" = "1" ] || [ "${RESTART_VIA}" = "1" ]; then
	info "starting ${VIA_NAME}"
	"${SCRIPTS_DIR}/start.sh" "${VIA_NAME}"
fi

echo
echo "published ${NAME} as ${DOMAIN} via ${VIA_NAME}"
echo "  upstream:  ${UPSTREAM}"
echo "  peers:     ${VIA_NAME} ALLOW_PEERS includes ${NAME}"
echo "  apply:     ./mvm argus apply"
if [ "${via_was_running}" != "1" ] && [ "${RESTART_VIA}" != "1" ]; then
	echo "  start:     ./mvm start ${VIA_NAME}"
fi
