#!/bin/sh
# Install host dependencies for mvm on Ubuntu, Debian, Arch, or Fedora.
#
# Usage:
#   ./scripts/install-deps.sh
#   ./scripts/install-deps.sh --with-go --with-shares
#   ./scripts/install-deps.sh --skip-firecracker
#   ./scripts/install-deps.sh --dry-run

set -eu

# shellcheck source=../lib/common.sh
. "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/lib/common.sh"

WITH_GO=0
WITH_SHARES=0
SKIP_FC=0
DRY_RUN=0
ASSUME_YES=0

usage() {
	cat <<'EOF'
Usage:
  ./scripts/install-deps.sh [options]

Options:
  --with-go           Install a Go toolchain (for ./mvm secrets)
  --with-shares       Install NFS server packages (HOST_SHARES)
  --skip-firecracker  Do not download the Firecracker binary
  --dry-run           Print actions without installing
  -y, --yes           Non-interactive package installs
  -h, --help          Show help
EOF
}

for arg in "$@"; do
	case "${arg}" in
	--with-go) WITH_GO=1 ;;
	--with-shares) WITH_SHARES=1 ;;
	--skip-firecracker) SKIP_FC=1 ;;
	--dry-run) DRY_RUN=1 ;;
	-y|--yes) ASSUME_YES=1 ;;
	-h|--help)
		usage
		exit 0
		;;
	*)
		die "unknown argument: ${arg}"
		;;
	esac
done

run() {
	if [ "${DRY_RUN}" = "1" ]; then
		echo "dry-run: $*"
		return 0
	fi
	"$@"
}

need_root() {
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	if [ "${DRY_RUN}" = "1" ]; then
		return 0
	fi
	die "install-deps needs root (try: $(root_helper 2>/dev/null || echo sudo) ./mvm deps ...)"
}

detect_family() {
	if [ -r /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		case "${ID:-}:${ID_LIKE:-}" in
		debian:*|ubuntu:*|*debian*|*ubuntu*)
			echo debian
			return 0
			;;
		fedora:*|*fedora*|*rhel*|*centos*)
			echo fedora
			return 0
			;;
		arch:*|*arch*)
			echo arch
			return 0
			;;
		esac
		case "${ID:-}" in
		debian|ubuntu|linuxmint|pop) echo debian; return 0 ;;
		fedora|rhel|centos|rocky|almalinux|nobara) echo fedora; return 0 ;;
		arch|endeavouros|manjaro|cachyos) echo arch; return 0 ;;
		esac
	fi
	if command -v apt-get >/dev/null 2>&1; then
		echo debian
		return 0
	fi
	if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
		echo fedora
		return 0
	fi
	if command -v pacman >/dev/null 2>&1; then
		echo arch
		return 0
	fi
	die "unsupported distro (need Ubuntu/Debian, Fedora/RHEL-like, or Arch)"
}

install_debian() {
	pkgs="curl python3 tar coreutils e2fsprogs iproute2 nftables dnsmasq conntrack bridge-utils util-linux bubblewrap git ca-certificates"
	if [ "${WITH_SHARES}" = "1" ]; then
		pkgs="${pkgs} nfs-kernel-server"
	fi
	if [ "${WITH_GO}" = "1" ]; then
		pkgs="${pkgs} golang-go"
	fi
	info "apt packages: ${pkgs}"
	export DEBIAN_FRONTEND=noninteractive
	run apt-get update
	# shellcheck disable=SC2086
	run apt-get install -y ${pkgs}
}

install_fedora() {
	pkgs="curl python3 tar coreutils e2fsprogs iproute nftables dnsmasq conntrack-tools util-linux bubblewrap git ca-certificates"
	if [ "${WITH_SHARES}" = "1" ]; then
		pkgs="${pkgs} nfs-utils"
	fi
	if [ "${WITH_GO}" = "1" ]; then
		pkgs="${pkgs} golang"
	fi
	info "dnf packages: ${pkgs}"
	if command -v dnf >/dev/null 2>&1; then
		# shellcheck disable=SC2086
		run dnf install -y ${pkgs}
	else
		# shellcheck disable=SC2086
		run yum install -y ${pkgs}
	fi
}

install_arch() {
	pkgs="curl python tar coreutils e2fsprogs iproute2 nftables dnsmasq conntrack-tools util-linux bubblewrap git ca-certificates"
	if [ "${WITH_SHARES}" = "1" ]; then
		pkgs="${pkgs} nfs-utils"
	fi
	if [ "${WITH_GO}" = "1" ]; then
		pkgs="${pkgs} go"
	fi
	info "pacman packages: ${pkgs}"
	# Refresh keyring first so fresh containers and mirrors keep working.
	if [ "${ASSUME_YES}" = "1" ] || [ "${DRY_RUN}" = "1" ]; then
		run pacman -Sy --needed --noconfirm archlinux-keyring || true
		# shellcheck disable=SC2086
		run pacman -Sy --needed --noconfirm ${pkgs}
	else
		run pacman -Sy --needed archlinux-keyring || true
		# shellcheck disable=SC2086
		run pacman -Sy --needed ${pkgs}
	fi
}

install_firecracker() {
	if command -v firecracker >/dev/null 2>&1; then
		info "firecracker already on PATH ($(command -v firecracker))"
		return 0
	fi
	require_cmd curl
	require_cmd tar
	arch="$(uname -m)"
	case "${arch}" in
	x86_64|aarch64) ;;
	arm64) arch=aarch64 ;;
	amd64) arch=x86_64 ;;
	*)
		die "unsupported arch for Firecracker: ${arch}"
		;;
	esac
	info "fetching latest Firecracker release for ${arch}"
	# Prefer the /releases/latest redirect (avoids api.github.com rate limits / 403 in CI).
	# Override with FIRECRACKER_VERSION=vX.Y.Z when needed.
	tag="${FIRECRACKER_VERSION:-}"
	if [ -z "${tag}" ]; then
		tag="$(
			basename "$(
				curl -fsSLI -o /dev/null -w '%{url_effective}' \
					https://github.com/firecracker-microvm/firecracker/releases/latest
			)"
		)"
	fi
	case "${tag}" in
	v[0-9]*) ;;
	*)
		die "could not resolve Firecracker release tag (got '${tag}')"
		;;
	esac
	url="https://github.com/firecracker-microvm/firecracker/releases/download/${tag}/firecracker-${tag}-${arch}.tgz"
	tmp="$(mktemp -d "${TMPDIR:-/tmp}/mvm-fc.XXXXXX")"
	info "downloading ${url}"
	run curl -fsSL -o "${tmp}/fc.tgz" "${url}"
	run tar -xzf "${tmp}/fc.tgz" -C "${tmp}"
	# Release layout: release-vX.Y.Z-ARCH/firecracker-vX.Y.Z-ARCH (not bare "firecracker").
	bin="${tmp}/release-${tag}-${arch}/firecracker-${tag}-${arch}"
	if [ ! -f "${bin}" ]; then
		bin="$(find "${tmp}" -type f \( -name "firecracker-${tag}-${arch}" -o -name firecracker \) ! -name '*.debug' | head -n1)"
	fi
	[ -n "${bin}" ] && [ -f "${bin}" ] || {
		rm -rf "${tmp}"
		die "firecracker binary missing from archive"
	}
	dest=/usr/local/bin/firecracker
	run install -m 755 "${bin}" "${dest}"
	rm -rf "${tmp}"
	info "installed ${dest} (${tag})"
}

verify_cmds() {
	missing=0
	for cmd in curl python3 tar truncate mkfs.ext4 ip nft dnsmasq; do
		if command -v "${cmd}" >/dev/null 2>&1; then
			echo "ok  ${cmd}"
		else
			echo "FAIL ${cmd}" >&2
			missing=1
		fi
	done
	if [ "${SKIP_FC}" != "1" ]; then
		if command -v firecracker >/dev/null 2>&1; then
			echo "ok  firecracker"
		else
			echo "FAIL firecracker" >&2
			missing=1
		fi
	fi
	if [ "${WITH_GO}" = "1" ]; then
		if command -v go >/dev/null 2>&1; then
			echo "ok  go"
		else
			echo "FAIL go" >&2
			missing=1
		fi
	fi
	if [ "${WITH_SHARES}" = "1" ]; then
		if command -v exportfs >/dev/null 2>&1; then
			echo "ok  exportfs"
		else
			echo "FAIL exportfs" >&2
			missing=1
		fi
	fi
	return "${missing}"
}

FAMILY="$(detect_family)"
info "detected package family: ${FAMILY}"
need_root

case "${FAMILY}" in
debian) install_debian ;;
fedora) install_fedora ;;
arch) install_arch ;;
*) die "unsupported family: ${FAMILY}" ;;
esac

if [ "${SKIP_FC}" != "1" ]; then
	install_firecracker
fi

echo
info "verifying commands"
if [ "${DRY_RUN}" = "1" ]; then
	echo "dry-run: skip verify"
	exit 0
fi
verify_cmds
echo
echo "host deps installed"
echo "next:"
echo "  cp -n config.example.env config.env"
echo "  ./mvm doctor"
echo "  ./mvm setup"
echo "  sudo ./mvm up demo alpine-shell"
