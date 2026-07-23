#!/bin/sh
# Bootstrap mvm on a new host.
#
# From a clone:
#   ./install.sh
#   ./install.sh --with-go --with-shares
#
# Curl one-liner (clones then installs):
#   curl -fsSL https://raw.githubusercontent.com/Sudo-Ivan/self-hosted-microvms/master/install.sh | sh
#
# Env:
#   MVM_INSTALL_DIR   clone destination (default: $HOME/self-hosted-microvms)
#   MVM_REPO          git URL
#   MVM_BRANCH        git branch (default: master)
#   MVM_SKIP_SETUP    set to 1 to skip ./mvm setup

set -eu

WITH_GO=0
WITH_SHARES=0
SKIP_FC=0
SKIP_SETUP="${MVM_SKIP_SETUP:-0}"
ASSUME_YES=0

usage() {
	cat <<'EOF'
Usage:
  ./install.sh [--with-go] [--with-shares] [--skip-firecracker] [--skip-setup] [-y]

Bootstrap host deps, config, and shared kernel/rootfs assets.
When run via curl|sh it clones the repo first.
EOF
}

for arg in "$@"; do
	case "${arg}" in
	--with-go) WITH_GO=1 ;;
	--with-shares) WITH_SHARES=1 ;;
	--skip-firecracker) SKIP_FC=1 ;;
	--skip-setup) SKIP_SETUP=1 ;;
	-y|--yes) ASSUME_YES=1 ;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		echo "unknown argument: ${arg}" >&2
		usage >&2
		exit 1
		;;
	esac
done

REPO_URL="${MVM_REPO:-https://github.com/Sudo-Ivan/self-hosted-microvms.git}"
BRANCH="${MVM_BRANCH:-master}"
INSTALL_DIR="${MVM_INSTALL_DIR:-${HOME}/self-hosted-microvms}"

resolve_root() {
	# Prefer an existing checkout when invoked as ./install.sh
	if [ -n "${1:-}" ] && [ -f "$1" ]; then
		_d=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd) || return 1
		if [ -x "${_d}/mvm" ] && [ -d "${_d}/scripts" ]; then
			printf '%s\n' "${_d}"
			return 0
		fi
	fi
	if [ -x ./mvm ] && [ -d ./scripts ]; then
		pwd
		return 0
	fi
	return 1
}

ROOT=
if ROOT="$(resolve_root "$0")"; then
	echo "==> using existing checkout ${ROOT}"
else
	if ! command -v git >/dev/null 2>&1; then
		echo "error: git is required to clone ${REPO_URL}" >&2
		exit 1
	fi
	if [ -d "${INSTALL_DIR}/.git" ] && [ -x "${INSTALL_DIR}/mvm" ]; then
		echo "==> using existing clone ${INSTALL_DIR}"
		ROOT="${INSTALL_DIR}"
	else
		echo "==> cloning ${REPO_URL} (${BRANCH}) into ${INSTALL_DIR}"
		mkdir -p "$(dirname -- "${INSTALL_DIR}")"
		if [ -e "${INSTALL_DIR}" ] && [ ! -d "${INSTALL_DIR}/.git" ]; then
			echo "error: ${INSTALL_DIR} exists and is not a git checkout" >&2
			exit 1
		fi
		if [ ! -d "${INSTALL_DIR}/.git" ]; then
			git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${INSTALL_DIR}"
		fi
		ROOT="${INSTALL_DIR}"
	fi
fi

cd "${ROOT}"

deps_flags=
if [ "${WITH_GO}" = "1" ]; then
	deps_flags="${deps_flags} --with-go"
fi
if [ "${WITH_SHARES}" = "1" ]; then
	deps_flags="${deps_flags} --with-shares"
fi
if [ "${SKIP_FC}" = "1" ]; then
	deps_flags="${deps_flags} --skip-firecracker"
fi
if [ "${ASSUME_YES}" = "1" ]; then
	deps_flags="${deps_flags} -y"
fi

echo "==> installing host dependencies"
# shellcheck disable=SC2086
if [ "$(id -u)" -eq 0 ]; then
	# shellcheck disable=SC2086
	./scripts/install-deps.sh ${deps_flags}
else
	if command -v doas >/dev/null 2>&1; then
		# shellcheck disable=SC2086
		doas ./scripts/install-deps.sh ${deps_flags}
	elif command -v sudo >/dev/null 2>&1; then
		# shellcheck disable=SC2086
		sudo ./scripts/install-deps.sh ${deps_flags}
	else
		echo "error: need root to install packages (install doas or sudo)" >&2
		exit 1
	fi
fi

if [ ! -f config.env ] && [ -f config.example.env ]; then
	cp -f config.example.env config.env
	echo "==> wrote config.env"
fi

if [ "${SKIP_SETUP}" != "1" ]; then
	if [ -r /dev/kvm ] && command -v firecracker >/dev/null 2>&1; then
		echo "==> running ./mvm setup"
		./mvm setup
	else
		echo "==> skip setup (need firecracker on PATH and readable /dev/kvm)"
		echo "    later: ./mvm setup"
	fi
fi

echo
echo "install complete: ${ROOT}"
echo
echo "easy first guest:"
echo "  cd ${ROOT}"
echo "  ./mvm templates"
echo "  ./mvm info alpine-shell"
if command -v doas >/dev/null 2>&1; then
	echo "  doas ./mvm up demo alpine-shell"
else
	echo "  sudo ./mvm up demo alpine-shell"
fi
echo "  ./mvm health demo"
echo
echo "list more apps with: ./mvm templates --tag=media"
