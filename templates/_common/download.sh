# Shared download helper for template install scripts.
# Usage: download_url URL DEST

set -eu

download_url() {
	url="$1"
	dest="$2"
	tmpdir="$(dirname "${dest}")"
	mkdir -p "${tmpdir}"
	echo "downloading ${url}"
	if command -v curl >/dev/null 2>&1; then
		curl -fL --progress-bar -o "${dest}.partial" "${url}"
	elif command -v wget >/dev/null 2>&1; then
		wget -O "${dest}.partial" "${url}"
	else
		echo "need curl or wget" >&2
		exit 1
	fi
	mv -f "${dest}.partial" "${dest}"
}

arch_go() {
	machine="$(uname -m)"
	case "${machine}" in
	x86_64) echo amd64 ;;
	aarch64|arm64) echo arm64 ;;
	*)
		echo "unsupported arch: ${machine}" >&2
		exit 1
		;;
	esac
}

arch_uname() {
	machine="$(uname -m)"
	case "${machine}" in
	x86_64|aarch64) echo "${machine}" ;;
	arm64) echo aarch64 ;;
	*)
		echo "unsupported arch: ${machine}" >&2
		exit 1
		;;
	esac
}
