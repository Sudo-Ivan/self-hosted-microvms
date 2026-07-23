# Host directory shares into guests via NFS.
# HOST_SHARES format: host_path:guest_path[:ro|rw]
# Multiple entries are comma separated.
# Example:
#   HOST_SHARES='/home/user/Music:/data/navidrome/music:ro'

shares_exports_file() {
	printf '/etc/exports.d/mvm-%s.exports\n' "${INSTANCE_NAME}"
}

shares_parse() {
	# Prints lines: host_path guest_path mode
	[ -n "${HOST_SHARES:-}" ] || return 0

	_sp_old_ifs=${IFS}
	IFS=,
	for entry in ${HOST_SHARES}; do
		IFS=${_sp_old_ifs}
		entry="$(echo "${entry}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -n "${entry}" ] || continue
		host_path="${entry%%:*}"
		rest="${entry#*:}"
		guest_path="${rest%%:*}"
		case "${rest}" in
		*:*)
			mode="${rest#*:}"
			;;
		*)
			mode="ro"
			;;
		esac
		case "${mode}" in
		ro|rw) ;;
		*) die "bad HOST_SHARES mode in '${entry}' (use ro or rw)" ;;
		esac
		[ -n "${host_path}" ] && [ -n "${guest_path}" ] || die "bad HOST_SHARES entry: ${entry}"
		case "${guest_path}" in
		/*) ;;
		*) die "guest path must be absolute: ${guest_path}" ;;
		esac
		case "${host_path}" in
		/*) ;;
		*) die "host path must be absolute: ${host_path}" ;;
		esac
		printf '%s\t%s\t%s\n' "${host_path}" "${guest_path}" "${mode}"
	done
}

shares_owner_ids() {
	path="$1"
	uid="$(stat -c '%u' "${path}" 2>/dev/null || stat -f '%u' "${path}")"
	gid="$(stat -c '%g' "${path}" 2>/dev/null || stat -f '%g' "${path}")"
	printf '%s %s\n' "${uid}" "${gid}"
}

shares_fsid() {
	# Stable small fsid from instance name and host path.
	printf '%s' "${INSTANCE_NAME}:$1" | cksum | awk '{print ($1 % 100000) + 1}'
}

shares_apply_host_exports() {
	[ -n "${HOST_SHARES:-}" ] || return 0

	if [ "$(id -u)" -ne 0 ]; then
		die "HOST_SHARES needs root (NFS export and guest rootfs update)"
	fi

	require_cmd exportfs
	exports_file="$(shares_exports_file)"
	mkdir -p /etc/exports.d
	: >"${exports_file}"

	while IFS="$(printf '\t')" read -r host_path guest_path mode; do
		[ -n "${host_path}" ] || continue
		[ -d "${host_path}" ] || die "HOST_SHARES host path missing: ${host_path}"
		set -- $(shares_owner_ids "${host_path}")
		uid=$1
		gid=$2
		fsid="$(shares_fsid "${host_path}")"
		opts="${mode},sync,no_subtree_check,all_squash,anonuid=${uid},anongid=${gid},fsid=${fsid}"
		printf '%s %s(%s)\n' "${host_path}" "${GUEST_IP}" "${opts}" >>"${exports_file}"
		echo "share export ${host_path} -> ${GUEST_IP} (${mode}, uid=${uid})"
	done <<EOF
$(shares_parse)
EOF

	if command -v systemctl >/dev/null 2>&1; then
		systemctl enable --now nfs-server 2>/dev/null \
			|| systemctl enable --now nfs-kernel-server 2>/dev/null \
			|| systemctl start nfs-server 2>/dev/null \
			|| systemctl start nfs-kernel-server 2>/dev/null \
			|| true
		systemctl start rpcbind 2>/dev/null || true
	fi

	if ! exportfs -r 2>/dev/null && ! exportfs -ra; then
		die "exportfs failed install nfs-utils and start nfs-server"
	fi

	# Show active exports for debugging.
	exportfs -v 2>/dev/null | head -n 20 || true
	echo "nfs exports updated (${exports_file})"
}

shares_remove_host_exports() {
	exports_file="$(shares_exports_file)"
	if [ "$(id -u)" -ne 0 ]; then
		return 0
	fi
	if [ -f "${exports_file}" ]; then
		rm -f "${exports_file}"
		exportfs -r 2>/dev/null || exportfs -ra 2>/dev/null || true
	fi
}

shares_write_guest_file() {
	# Write /etc/microvm-shares into the guest rootfs image.
	# Also refreshes guest boot scripts and the service template.
	# shellcheck source=guestfs.sh
	. "${LIB_DIR}/guestfs.sh"

	guestfs_sync_template

	[ -n "${HOST_SHARES:-}" ] || return 0

	guestfs_mount_rootfs
	: >"${GUESTFS_MNT}/etc/microvm-shares"
	while IFS="$(printf '\t')" read -r host_path guest_path mode; do
		[ -n "${host_path}" ] || continue
		printf 'nfs\t%s\t%s\t%s\n' "${host_path}" "${guest_path}" "${mode}" \
			>>"${GUESTFS_MNT}/etc/microvm-shares"
	done <<EOF
$(shares_parse)
EOF
	guestfs_umount
	echo "guest share config written"
}
