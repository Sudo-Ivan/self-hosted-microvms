#!/bin/sh
# Show details for one template.
#
# Usage:
#   ./scripts/info.sh <template>

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

NAME="${1:-}"
[ -n "${NAME}" ] || die "usage: ./mvm info <template>"

load_template "${NAME}"

host_port=""
if [ -n "${TEMPLATE_PORT_FORWARDS}" ]; then
	first="${TEMPLATE_PORT_FORWARDS%%,*}"
	first="$(echo "${first}" | tr -d '[:space:]')"
	host_port="${first%%:*}"
fi
if [ -z "${host_port}" ] && [ -n "${TEMPLATE_HEALTH_PORT}" ]; then
	host_port="${TEMPLATE_HEALTH_PORT}"
fi

scheme="${TEMPLATE_HEALTH_SCHEME:-http}"
url="(no published http port)"
if [ -n "${host_port}" ]; then
	url="${scheme}://127.0.0.1:${host_port}/"
fi

cat <<EOF
template:     ${TEMPLATE_NAME}
description:  ${TEMPLATE_DESCRIPTION:-}
tags:         ${TEMPLATE_TAGS:-none}
memory:       ${TEMPLATE_MEM_MIB} MiB
vcpus:        ${TEMPLATE_VCPU_COUNT}
rootfs:       ${TEMPLATE_ROOTFS_SIZE_MIB} MiB
data disk:    ${TEMPLATE_DATA_SIZE_MIB} MiB
ports:        ${TEMPLATE_PORT_FORWARDS:-none}
health:       ${scheme} :${TEMPLATE_HEALTH_PORT:-auto}${TEMPLATE_HEALTH_PATH}
data:         ${TEMPLATE_DATA_HINT}
packages:     ${TEMPLATE_PACKAGES:-none}
path:         ${TEMPLATE_DIR}

example:
  ./mvm up ${TEMPLATE_NAME} ${TEMPLATE_NAME}
  ./mvm health ${TEMPLATE_NAME}
  open ${url}
EOF

if [ -n "${TEMPLATE_NOTES}" ]; then
	echo
	echo "notes:"
	echo "  ${TEMPLATE_NOTES}"
fi

if [ -f "${TEMPLATE_DIR}/firewall.env" ]; then
	echo
	echo "firewall defaults: ${TEMPLATE_DIR}/firewall.env"
fi
