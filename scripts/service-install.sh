#!/bin/sh
# Install init-system unit files for mvm.
#
# Usage:
#   sudo ./scripts/service-install.sh install systemd
#   sudo ./scripts/service-install.sh install openrc
#   sudo ./scripts/service-install.sh install runit
#   sudo ./scripts/service-install.sh install dinit
#   sudo ./scripts/service-install.sh enable <name> [systemd|openrc|runit|dinit]
#   sudo ./scripts/service-install.sh disable <name> [systemd|openrc|runit|dinit]
#   ./scripts/service-install.sh list

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"
load_config

INIT_SRC="${REPO_ROOT}/init"
ACTION="${1:-}"
shift 2>/dev/null || :

render() {
	src="$1"
	dest="$2"
	instance="${3:-}"
	mkdir -p "$(dirname "${dest}")"
	sed \
		-e "s|@MVM_ROOT@|${REPO_ROOT}|g" \
		-e "s|@INSTANCE@|${instance}|g" \
		"${src}" >"${dest}"
	chmod 755 "${dest}" 2>/dev/null || true
	# Unit files should not be executable.
	case "${dest}" in
	*.service|*/dinit/*|*/mvm-argus|*/mvm-watchdog|*/mvm|*/mvm.*)
		case "${dest}" in
		*.service|*/dinit/*)
			;;
		*)
			;;
		esac
		if false; then
			chmod 644 "${dest}"
		fi
		;;
	esac
	case "${dest}" in
	*.service)
		chmod 644 "${dest}"
		;;
	esac
	case "${dest}" in
	*/dinit/*)
		chmod 644 "${dest}"
		;;
	esac
	if [ "$(basename "$(dirname "${dest}")")" = "dinit.d" ]; then
		chmod 644 "${dest}"
	fi
}

detect_init() {
	if [ -d /run/systemd/system ] || command -v systemctl >/dev/null 2>&1; then
		echo systemd
	elif [ -d /etc/runit ] || command -v sv >/dev/null 2>&1; then
		echo runit
	elif command -v dinitctl >/dev/null 2>&1 || [ -d /etc/dinit.d ]; then
		echo dinit
	elif command -v rc-update >/dev/null 2>&1 || [ -d /etc/init.d ]; then
		echo openrc
	else
		die "could not detect init system (pass systemd|openrc|runit|dinit)"
	fi
}

install_systemd() {
	unitdir="/etc/systemd/system"
	render "${INIT_SRC}/systemd/mvm-argus.service" "${unitdir}/mvm-argus.service"
	render "${INIT_SRC}/systemd/mvm@.service" "${unitdir}/mvm@.service"
	render "${INIT_SRC}/systemd/mvm-watchdog.service" "${unitdir}/mvm-watchdog.service"
	systemctl daemon-reload
	systemctl enable mvm-argus.service
	echo "installed systemd units in ${unitdir}"
	echo "  sudo systemctl enable --now mvm-argus"
	echo "  sudo systemctl enable --now mvm@NAME"
	echo "  sudo systemctl enable --now mvm-watchdog"
}

install_openrc() {
	initd="/etc/init.d"
	render "${INIT_SRC}/openrc/mvm-argus" "${initd}/mvm-argus"
	render "${INIT_SRC}/openrc/mvm" "${initd}/mvm"
	render "${INIT_SRC}/openrc/mvm-watchdog" "${initd}/mvm-watchdog"
	chmod 755 "${initd}/mvm-argus" "${initd}/mvm" "${initd}/mvm-watchdog"
	rc-update add mvm-argus default 2>/dev/null || true
	echo "installed openrc scripts in ${initd}"
	echo "  sudo rc-service mvm-argus start"
	echo "  sudo ./mvm service enable NAME openrc"
	echo "  sudo rc-update add mvm-watchdog default"
}

install_runit() {
	svdir="${MVM_RUNIT_DIR:-/etc/sv}"
	mkdir -p "${svdir}/mvm-argus" "${svdir}/mvm-watchdog"
	render "${INIT_SRC}/runit/mvm-argus/run" "${svdir}/mvm-argus/run"
	render "${INIT_SRC}/runit/mvm-argus/finish" "${svdir}/mvm-argus/finish"
	render "${INIT_SRC}/runit/mvm-watchdog/run" "${svdir}/mvm-watchdog/run"
	chmod 755 "${svdir}/mvm-argus/run" "${svdir}/mvm-argus/finish" "${svdir}/mvm-watchdog/run"
	echo "installed runit services in ${svdir}"
	echo "  sudo ln -s ${svdir}/mvm-argus /var/service/mvm-argus"
	echo "  sudo ./mvm service enable NAME runit"
	echo "  sudo ln -s ${svdir}/mvm-watchdog /var/service/mvm-watchdog"
}

install_dinit() {
	ddir="${MVM_DINIT_DIR:-/etc/dinit.d}"
	mkdir -p "${ddir}"
	render "${INIT_SRC}/dinit/mvm-argus" "${ddir}/mvm-argus"
	render "${INIT_SRC}/dinit/mvm-watchdog" "${ddir}/mvm-watchdog"
	chmod 644 "${ddir}/mvm-argus" "${ddir}/mvm-watchdog"
	echo "installed dinit services in ${ddir}"
	echo "  sudo dinitctl enable mvm-argus"
	echo "  sudo ./mvm service enable NAME dinit"
	echo "  sudo dinitctl enable mvm-watchdog"
}

enable_instance() {
	name="$1"
	kind="${2:-$(detect_init)}"
	validate_name "${name}"
	[ -d "$(instance_dir "${name}")" ] || die "instance not found: ${name}"

	case "${kind}" in
	systemd)
		systemctl enable --now "mvm-argus.service"
		systemctl enable --now "mvm@${name}.service"
		echo "enabled systemd mvm@${name}"
		;;
	openrc)
		initd="/etc/init.d/mvm.${name}"
		confd="/etc/conf.d/mvm.${name}"
		render "${INIT_SRC}/openrc/mvm" "${initd}"
		chmod 755 "${initd}"
		printf 'instance="%s"\n' "${name}" >"${confd}"
		rc-update add "mvm.${name}" default 2>/dev/null || true
		rc-service "mvm.${name}" start
		echo "enabled openrc mvm.${name}"
		;;
	runit)
		svdir="${MVM_RUNIT_DIR:-/etc/sv}"
		svc="${svdir}/mvm-${name}"
		live="${MVM_RUNIT_LIVE:-/var/service}"
		mkdir -p "${svc}"
		render "${INIT_SRC}/runit/mvm-instance/run" "${svc}/run" "${name}"
		render "${INIT_SRC}/runit/mvm-instance/finish" "${svc}/finish" "${name}"
		chmod 755 "${svc}/run" "${svc}/finish"
		ln -sfn "${svc}" "${live}/mvm-${name}"
		echo "enabled runit mvm-${name}"
		;;
	dinit)
		ddir="${MVM_DINIT_DIR:-/etc/dinit.d}"
		render "${INIT_SRC}/dinit/mvm-instance" "${ddir}/mvm-${name}" "${name}"
		chmod 644 "${ddir}/mvm-${name}"
		dinitctl enable "mvm-${name}" 2>/dev/null || true
		dinitctl start "mvm-${name}" 2>/dev/null || true
		echo "enabled dinit mvm-${name}"
		;;
	*)
		die "unknown init: ${kind}"
		;;
	esac
}

disable_instance() {
	name="$1"
	kind="${2:-$(detect_init)}"
	validate_name "${name}"

	case "${kind}" in
	systemd)
		systemctl disable --now "mvm@${name}.service" 2>/dev/null || true
		echo "disabled systemd mvm@${name}"
		;;
	openrc)
		rc-service "mvm.${name}" stop 2>/dev/null || true
		rc-update del "mvm.${name}" default 2>/dev/null || true
		rm -f "/etc/init.d/mvm.${name}" "/etc/conf.d/mvm.${name}"
		echo "disabled openrc mvm.${name}"
		;;
	runit)
		live="${MVM_RUNIT_LIVE:-/var/service}"
		svdir="${MVM_RUNIT_DIR:-/etc/sv}"
		rm -f "${live}/mvm-${name}"
		rm -rf "${svdir}/mvm-${name}"
		echo "disabled runit mvm-${name}"
		;;
	dinit)
		ddir="${MVM_DINIT_DIR:-/etc/dinit.d}"
		dinitctl stop "mvm-${name}" 2>/dev/null || true
		dinitctl disable "mvm-${name}" 2>/dev/null || true
		rm -f "${ddir}/mvm-${name}"
		echo "disabled dinit mvm-${name}"
		;;
	*)
		die "unknown init: ${kind}"
		;;
	esac
}

case "${ACTION}" in
install)
	require_root
	kind="${1:-$(detect_init)}"
	case "${kind}" in
	systemd) install_systemd ;;
	openrc) install_openrc ;;
	runit) install_runit ;;
	dinit) install_dinit ;;
	*) die "unknown init: ${kind}" ;;
	esac
	;;
enable)
	require_root
	[ -n "${1:-}" ] || die "usage: $0 enable <name> [init]"
	enable_instance "$1" "${2:-}"
	;;
disable)
	require_root
	[ -n "${1:-}" ] || die "usage: $0 disable <name> [init]"
	disable_instance "$1" "${2:-}"
	;;
list)
	echo "bundled init files under init/"
	echo "  systemd openrc runit dinit"
	echo "detected: $(detect_init)"
	;;
""|-h|--help)
	sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
	;;
*)
	die "unknown action: ${ACTION}"
	;;
esac
