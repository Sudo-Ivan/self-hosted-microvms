# Backup and rollback helpers.

BACKUPS_DIR="${BACKUPS_DIR:-${SHARED_DIR}/backups}"

backup_dirs_for() {
	name="$1"
	printf '%s/%s\n' "${BACKUPS_DIR}" "${name}"
}

backup_create() {
	name="$1"
	label="${2:-manual}"
	load_instance "${name}"
	dir="$(backup_dirs_for "${name}")"
	stamp="$(date -u +%Y%m%dT%H%M%SZ)"
	dest="${dir}/${stamp}"
	mkdir -p "${dest}"

	info "backing up ${name} to ${dest}"
	cp -a "${INSTANCE_DIR}/config.env" "${dest}/config.env"
	if [ -f "${INSTANCE_DIR}/firewall.env" ]; then
		cp -a "${INSTANCE_DIR}/firewall.env" "${dest}/firewall.env"
	fi
	cp -a "${DATA_PATH}" "${dest}/data.ext4"
	# Rootfs is large and usually recoverable from template. Opt in with BACKUP_ROOTFS=1.
	if [ "${BACKUP_ROOTFS:-0}" = "1" ]; then
		cp -a "${ROOTFS_PATH}" "${dest}/rootfs.ext4"
	fi
	printf '%s\n' "${label}" >"${dest}/label"
	printf '%s\n' "${stamp}" >"${dest}/stamp"
	ln -sfn "${stamp}" "${dir}/latest"
	echo "${dest}"
}

backup_list() {
	name="${1:-}"
	if [ -n "${name}" ]; then
		dir="$(backup_dirs_for "${name}")"
		[ -d "${dir}" ] || {
			echo "(no backups for ${name})"
			return 0
		}
		printf '%-14s %-20s %-10s %s\n' "INSTANCE" "STAMP" "SIZE" "LABEL"
		for stamp in "${dir}"/20*; do
			[ -d "${stamp}" ] || continue
			label="$(cat "${stamp}/label" 2>/dev/null || echo manual)"
			size="$(du -sh "${stamp}" 2>/dev/null | awk '{print $1}')"
			printf '%-14s %-20s %-10s %s\n' "${name}" "$(basename "${stamp}")" "${size}" "${label}"
		done
		return 0
	fi

	printf '%-14s %-20s %-10s %s\n' "INSTANCE" "STAMP" "SIZE" "LABEL"
	for dir in "${BACKUPS_DIR}"/*/; do
		name="$(basename "${dir}")"
		for stamp in "${dir}"/20*; do
			[ -d "${stamp}" ] || continue
			label="$(cat "${stamp}/label" 2>/dev/null || echo manual)"
			size="$(du -sh "${stamp}" 2>/dev/null | awk '{print $1}')"
			printf '%-14s %-20s %-10s %s\n' "${name}" "$(basename "${stamp}")" "${size}" "${label}"
		done
	done
}

backup_resolve() {
	name="$1"
	stamp="${2:-latest}"
	dir="$(backup_dirs_for "${name}")"
	if [ "${stamp}" = "latest" ]; then
		[ -L "${dir}/latest" ] || [ -f "${dir}/latest" ] || die "no latest backup for ${name}"
		stamp="$(readlink "${dir}/latest" 2>/dev/null || cat "${dir}/latest")"
	fi
	dest="${dir}/${stamp}"
	[ -d "${dest}" ] || die "backup not found: ${name}/${stamp}"
	printf '%s\n' "${dest}"
}

backup_restore() {
	name="$1"
	stamp="${2:-latest}"
	dest="$(backup_resolve "${name}" "${stamp}")"
	load_instance "${name}"
	was_running=0

	if is_running "${PID_FILE}"; then
		was_running=1
		info "stopping ${name} for restore"
		"${SCRIPTS_DIR}/stop.sh" "${name}"
	fi

	info "restoring ${name} from $(basename "${dest}")"
	cp -a "${dest}/data.ext4" "${DATA_PATH}"
	if [ -f "${dest}/rootfs.ext4" ]; then
		cp -a "${dest}/rootfs.ext4" "${ROOTFS_PATH}"
	fi
	if [ -f "${dest}/firewall.env" ]; then
		cp -a "${dest}/firewall.env" "${INSTANCE_DIR}/firewall.env"
	fi

	if [ "${was_running}" = "1" ]; then
		info "starting ${name}"
		run_as_root "$(mvm_bin)" start "${name}"
	fi
	echo "restored ${name} from ${dest}"
}

backup_prune() {
	name="$1"
	keep="${2:-5}"
	dir="$(backup_dirs_for "${name}")"
	[ -d "${dir}" ] || return 0
	count="$(find "${dir}" -mindepth 1 -maxdepth 1 -type d -name '20*' | wc -l)"
	if [ "${count}" -le "${keep}" ]; then
		return 0
	fi
	find "${dir}" -mindepth 1 -maxdepth 1 -type d -name '20*' \
		| sort \
		| head -n "$((count - keep))" \
		| while read -r old; do
			info "pruning backup ${old}"
			rm -rf "${old}"
		done
	# Refresh latest pointer.
	newest="$(find "${dir}" -mindepth 1 -maxdepth 1 -type d -name '20*' | sort | tail -n 1)"
	if [ -n "${newest}" ]; then
		ln -sfn "$(basename "${newest}")" "${dir}/latest"
	fi
}
