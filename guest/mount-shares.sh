#!/bin/sh
# Mount host directory shares listed in /etc/microvm-shares.
# Must run after networking and package install (nfs-utils).

set -eu

SHARES_FILE="${1:-/etc/microvm-shares}"

if [ ! -f "${SHARES_FILE}" ]; then
	exit 0
fi

if [ -f /etc/microvm-net ]; then
	# shellcheck disable=SC1091
	. /etc/microvm-net
fi

GATEWAY="${GATEWAY:-10.100.0.1}"
failed=0

while IFS="$(printf '\t')" read -r share_type host_export guest_mount share_mode; do
	[ -n "${share_type}" ] || continue
	case "${share_type}" in
	\#*) continue ;;
	esac

	mkdir -p "${guest_mount}"
	share_mode="${share_mode:-ro}"

	case "${share_type}" in
	nfs)
		umount "${guest_mount}" 2>/dev/null || true
		opts="${share_mode},nolock,tcp,timeo=50,retrans=3"
		if mount -t nfs4 -o "${opts}" "${GATEWAY}:${host_export}" "${guest_mount}"; then
			echo "mounted share ${GATEWAY}:${host_export} -> ${guest_mount} (${share_mode})"
			continue
		fi
		if mount -t nfs -o "vers=3,${opts}" "${GATEWAY}:${host_export}" "${guest_mount}"; then
			echo "mounted share (nfs3) ${GATEWAY}:${host_export} -> ${guest_mount} (${share_mode})"
			continue
		fi
		echo "failed to mount share ${GATEWAY}:${host_export} -> ${guest_mount}" >&2
		failed=1
		;;
	*)
		echo "unknown share type: ${share_type}" >&2
		failed=1
		;;
	esac
done <"${SHARES_FILE}"

if [ "${failed}" -ne 0 ]; then
	exit 1
fi
