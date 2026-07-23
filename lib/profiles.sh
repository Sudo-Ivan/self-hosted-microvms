# Profile loading for create and up.

PROFILES_DIR="${PROFILES_DIR:-${REPO_ROOT}/profiles}"

list_profiles() {
	for f in "${PROFILES_DIR}"/*.env; do
		name="$(basename "${f}" .env)"
		# shellcheck disable=SC1090
		DESCRIPTION=""
		MEM_MIB=""
		VCPU_COUNT=""
		DATA_SIZE_MIB=""
		# shellcheck disable=SC1091
		. "${f}"
		printf '%-12s mem=%-5s vcpu=%-2s data=%-5s  %s\n' \
			"${name}" \
			"${MEM_MIB:-?}M" \
			"${VCPU_COUNT:-?}" \
			"${DATA_SIZE_MIB:-?}M" \
			"${DESCRIPTION:-}"
	done
}

load_profile() {
	name="$1"
	f="${PROFILES_DIR}/${name}.env"
	[ -f "${f}" ] || die "profile not found: ${name} (try ./mvm profiles)"

	PROFILE_NAME="${name}"
	PROFILE_MEM_MIB=""
	PROFILE_VCPU_COUNT=""
	PROFILE_DATA_SIZE_MIB=""
	PROFILE_ROOTFS_SIZE_MIB=""

	# shellcheck disable=SC1090
	set -a
	# shellcheck disable=SC1091
	. "${f}"
	set +a

	PROFILE_MEM_MIB="${MEM_MIB:-}"
	PROFILE_VCPU_COUNT="${VCPU_COUNT:-}"
	PROFILE_DATA_SIZE_MIB="${DATA_SIZE_MIB:-}"
	PROFILE_ROOTFS_SIZE_MIB="${ROOTFS_SIZE_MIB:-}"
	# Clear so template load does not inherit profile keys as template defaults.
	unset MEM_MIB VCPU_COUNT DATA_SIZE_MIB ROOTFS_SIZE_MIB DESCRIPTION PROFILE
}

apply_profile_to_create_vars() {
	# Profile fills gaps only. Explicit caller values already live in USER_*.
	if [ -z "${USER_MEM_MIB}" ] && [ -n "${PROFILE_MEM_MIB:-}" ]; then
		USER_MEM_MIB="${PROFILE_MEM_MIB}"
	fi
	if [ -z "${USER_VCPU_COUNT}" ] && [ -n "${PROFILE_VCPU_COUNT:-}" ]; then
		USER_VCPU_COUNT="${PROFILE_VCPU_COUNT}"
	fi
	if [ -z "${USER_DATA_SIZE_MIB}" ] && [ -n "${PROFILE_DATA_SIZE_MIB:-}" ]; then
		USER_DATA_SIZE_MIB="${PROFILE_DATA_SIZE_MIB}"
	fi
	if [ -z "${USER_ROOTFS_SIZE_MIB}" ] && [ -n "${PROFILE_ROOTFS_SIZE_MIB:-}" ]; then
		USER_ROOTFS_SIZE_MIB="${PROFILE_ROOTFS_SIZE_MIB}"
	fi
}
