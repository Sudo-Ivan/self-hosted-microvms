# Guest rootfs and disk image helpers (host-side, usually needs root).

guestfs_require_root() {
	[ "$(id -u)" -eq 0 ] || die "guest rootfs update needs root (try: $(root_helper) $(mvm_bin) ...)"
}

guestfs_mount_rootfs() {
	# Mount ROOTFS_PATH read-write. Sets GUESTFS_MNT. Caller must guestfs_umount.
	guestfs_require_root
	[ -f "${ROOTFS_PATH}" ] || die "missing rootfs: ${ROOTFS_PATH}"
	GUESTFS_MNT="$(mktemp -d "${INSTANCE_DIR}/rootfs-mnt.XXXXXX")"
	mount -o loop,rw "${ROOTFS_PATH}" "${GUESTFS_MNT}"
}

guestfs_umount() {
	if [ -n "${GUESTFS_MNT:-}" ] && [ -d "${GUESTFS_MNT}" ]; then
		sync
		umount "${GUESTFS_MNT}" 2>/dev/null || umount -l "${GUESTFS_MNT}" 2>/dev/null || true
		rmdir "${GUESTFS_MNT}" 2>/dev/null || true
		GUESTFS_MNT=""
	fi
}

guestfs_sync_template() {
	# Copy current host template + guest boot scripts into the instance rootfs.
	guestfs_require_root
	[ -n "${TEMPLATE:-}" ] || die "TEMPLATE unset for instance ${INSTANCE_NAME:-?}"
	[ -d "${TEMPLATES_DIR}/${TEMPLATE}" ] || die "template not found: ${TEMPLATE}"

	guestfs_mount_rootfs
	mnt="${GUESTFS_MNT}"
	mkdir -p "${mnt}/etc/microvm" "${mnt}/opt/template"

	cp -f "${GUEST_DIR}/init" "${mnt}/init"
	cp -f "${GUEST_DIR}/first-boot.sh" "${mnt}/etc/microvm/first-boot.sh"
	cp -f "${GUEST_DIR}/run-service.sh" "${mnt}/etc/microvm/run-service.sh"
	cp -f "${GUEST_DIR}/update-guest.sh" "${mnt}/etc/microvm/update-guest.sh"
	cp -f "${GUEST_DIR}/mount-shares.sh" "${mnt}/etc/microvm/mount-shares.sh"
	cp -f "${GUEST_DIR}/fetch-secrets.sh" "${mnt}/etc/microvm/fetch-secrets.sh"
	cp -f "${GUEST_DIR}/prepare-harden.sh" "${mnt}/etc/microvm/prepare-harden.sh"
	cp -f "${GUEST_DIR}/harden-exec.sh" "${mnt}/etc/microvm/harden-exec.sh"
	chmod 755 \
		"${mnt}/init" \
		"${mnt}/etc/microvm/first-boot.sh" \
		"${mnt}/etc/microvm/run-service.sh" \
		"${mnt}/etc/microvm/update-guest.sh" \
		"${mnt}/etc/microvm/mount-shares.sh" \
		"${mnt}/etc/microvm/fetch-secrets.sh" \
		"${mnt}/etc/microvm/prepare-harden.sh" \
		"${mnt}/etc/microvm/harden-exec.sh"

	rm -rf "${mnt}/opt/template"
	mkdir -p "${mnt}/opt/template"
	cp -a "${TEMPLATES_DIR}/${TEMPLATE}/." "${mnt}/opt/template/"
	if [ -d "${TEMPLATES_DIR}/_common" ]; then
		mkdir -p "${mnt}/opt/template/_common"
		cp -a "${TEMPLATES_DIR}/_common/." "${mnt}/opt/template/_common/"
	fi
	chmod 755 "${mnt}/opt/template/"*.sh 2>/dev/null || true
	chmod 755 "${mnt}/opt/template/_common/"*.sh 2>/dev/null || true

	guestfs_umount
	info "synced template ${TEMPLATE} into ${INSTANCE_NAME} rootfs"
}

image_size_mib() {
	path="$1"
	bytes="$(stat -c%s "${path}")"
	echo $(( (bytes + 1048575) / 1048576 ))
}

grow_ext4_image() {
	# Grow an ext4 image file to target_mib. Never shrinks.
	path="$1"
	target_mib="$2"
	current=

	[ -f "${path}" ] || die "missing image: ${path}"
	case "${target_mib}" in
	*[!0-9]*|'')
		die "size must be an integer MiB: ${target_mib}"
		;;
	esac
	if [ "${target_mib}" -lt 64 ]; then
		die "size too small: ${target_mib} MiB"
	fi

	current="$(image_size_mib "${path}")"
	if [ "${target_mib}" -lt "${current}" ]; then
		die "refusing to shrink ${path} from ${current} MiB to ${target_mib} MiB"
	fi
	if [ "${target_mib}" -eq "${current}" ]; then
		echo "${path} already ${current} MiB"
		return 0
	fi

	require_cmd truncate
	require_cmd e2fsck
	require_cmd resize2fs

	info "growing ${path}: ${current} -> ${target_mib} MiB"
	truncate -s "${target_mib}M" "${path}"
	e2fsck -f -y "${path}" >/dev/null
	resize2fs "${path}" >/dev/null
}

config_set_kv() {
	# Set KEY='value' in an instance config.env (create or replace line).
	file="$1"
	key="$2"
	value="$3"

	[ -f "${file}" ] || die "missing ${file}"
	tmp="$(mktemp)"
	if grep -q "^${key}=" "${file}"; then
		awk -v key="${key}" -v value="${value}" '
			BEGIN { q = sprintf("%c", 39) }
			index($0, key "=") == 1 {
				print key "=" q value q
				next
			}
			{ print }
		' "${file}" >"${tmp}"
	else
		cat "${file}" >"${tmp}"
		printf "%s='%s'\n" "${key}" "${value}" >>"${tmp}"
	fi
	mv -f "${tmp}" "${file}"
}
