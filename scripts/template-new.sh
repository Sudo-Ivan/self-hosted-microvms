#!/bin/sh
# Scaffold a new service template.
#
# Usage:
#   ./scripts/template-new.sh <name> [--port N] [--tag TAG] [--desc TEXT] [--mem MiB]
#   ./mvm template new myapp --port 8080 --tag tools --desc "My service"

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME=""
PORT="8080"
TAG="misc"
DESC=""
MEM="256"
VCPU="1"

usage() {
	cat <<'EOF'
Usage:
  ./mvm template new <name> [--port N] [--tag TAG] [--desc TEXT] [--mem MiB]

Creates templates/<name>/{manifest.env,install.sh,run.sh,update.sh} and runs validate.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--port)
		PORT="$2"
		shift 2
		;;
	--tag)
		TAG="$2"
		shift 2
		;;
	--desc|--description)
		DESC="$2"
		shift 2
		;;
	--mem)
		MEM="$2"
		shift 2
		;;
	--vcpu)
		VCPU="$2"
		shift 2
		;;
	-h|--help)
		usage
		exit 0
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

[ -n "${NAME}" ] || {
	usage >&2
	exit 1
}
validate_name "${NAME}"
[ "${NAME}" != "_common" ] || die "reserved template name: _common"

DIR="$(template_dir "${NAME}")"
[ ! -e "${DIR}" ] || die "template already exists: ${DIR}"

if [ -z "${DESC}" ]; then
	DESC="${NAME} service"
fi

UPPER="$(printf '%s' "${NAME}" | tr '[:lower:]-' '[:upper:]_')"
VERSION_VAR="${UPPER}_VERSION"

mkdir -p "${DIR}"

cat >"${DIR}/manifest.env" <<EOF
DESCRIPTION="${DESC}"
MEM_MIB=${MEM}
VCPU_COUNT=${VCPU}
DATA_SIZE_MIB=1024
ROOTFS_SIZE_MIB=1024
PORT_FORWARDS=${PORT}:${PORT}
HEALTH_PATH=/
HEALTH_PORT=${PORT}
PACKAGES="ca-certificates curl"
TAGS=${TAG}
DATA_HINT=/data/${NAME}
HARDEN=setpriv
NOTES="Bump ${VERSION_VAR} in install.sh then ./mvm template sync <instance> && ./mvm update <instance>"
EOF

cat >"${DIR}/install.sh" <<EOF
#!/bin/sh
# Install ${NAME}.
# Upstream: https://example.com/${NAME}

set -eu

# shellcheck disable=SC1091
. /opt/template/_common/download.sh

VERSION="\${${VERSION_VAR}:-0.1.0}"
ARCH="\$(arch_go)"
# Replace URL with the real release asset.
URL="https://example.com/releases/\${VERSION}/${NAME}_linux_\${ARCH}.tar.gz"

mkdir -p /opt/service /data/${NAME}
download_url "\${URL}" /tmp/${NAME}.tgz
tar -xzf /tmp/${NAME}.tgz -C /tmp
bin="\$(find /tmp -type f -name ${NAME} | head -n1)"
[ -n "\${bin}" ] || { echo "${NAME} binary missing after extract" >&2; exit 1; }
cp -f "\${bin}" /opt/service/${NAME}
chmod 755 /opt/service/${NAME}
rm -rf /tmp/${NAME}.tgz
EOF

cat >"${DIR}/run.sh" <<EOF
#!/bin/sh
# Start ${NAME} with state on the data volume.

set -eu

mkdir -p /data/${NAME}
exec /opt/service/${NAME}
EOF

cat >"${DIR}/update.sh" <<EOF
#!/bin/sh
# Re-run install on guest update (./mvm update <instance>).

set -eu

exec /opt/template/install.sh
EOF

chmod 755 "${DIR}/install.sh" "${DIR}/run.sh" "${DIR}/update.sh"

info "created template ${NAME} at ${DIR}"
"${SCRIPTS_DIR}/validate-templates.sh" >/dev/null || {
	echo "scaffold created but validate reported issues (expected until install URL is real)"
}

echo
echo "next:"
echo "  1. edit ${DIR}/install.sh (pin ${VERSION_VAR}, fix download URL)"
echo "  2. edit ${DIR}/run.sh (real CLI flags and ports)"
echo "  3. ./mvm validate && ./mvm info ${NAME}"
echo "  4. ./mvm up demo ${NAME}"
echo "later updates:"
echo "  bump ${VERSION_VAR} then: ./mvm template sync <instance> && ./mvm update <instance>"
