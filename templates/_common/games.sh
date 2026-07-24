# Shared helpers for non-Minecraft game templates.
# Source after set -eu. Requires python3 and curl where used.

games_ua() {
	printf '%s\n' "mvm-games/1.0"
}

games_arch_uname() {
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

games_arch_openttd() {
	machine="$(uname -m)"
	case "${machine}" in
	x86_64) echo amd64 ;;
	aarch64|arm64) echo arm64 ;;
	*)
		echo "unsupported arch for OpenTTD: ${machine}" >&2
		exit 1
		;;
	esac
}

games_download() {
	url="$1"
	dest="$2"
	mkdir -p "$(dirname "${dest}")"
	echo "downloading ${url}"
	curl -fL -A "$(games_ua)" --progress-bar -o "${dest}.partial" "${url}"
	mv -f "${dest}.partial" "${dest}"
}

# Print browser_download_url for the first GitHub release asset matching regex.
# Usage: games_github_asset owner/repo 'regex' [tag|latest]
games_github_asset() {
	repo="$1"
	pattern="$2"
	tag="${3:-latest}"
	REPO="${repo}" PATTERN="${pattern}" TAG="${tag}" python3 <<'PY'
import json, os, re, sys, urllib.request

repo = os.environ["REPO"]
pattern = re.compile(os.environ["PATTERN"])
tag = os.environ.get("TAG", "latest")
ua = {"User-Agent": "mvm-games/1.0"}
if tag == "latest":
	url = f"https://api.github.com/repos/{repo}/releases/latest"
else:
	url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
data = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=ua)))
for asset in data.get("assets", []):
	name = asset.get("name") or ""
	if pattern.search(name):
		print(data.get("tag_name") or tag)
		print(name)
		print(asset["browser_download_url"])
		sys.exit(0)
sys.stderr.write(f"no asset matching /{pattern.pattern}/ in {repo}@{tag}\n")
sys.exit(1)
PY
}

# Factorio headless latest stable (or FACTORIO_VERSION=x.y.z). Prints: VERSION URL
games_resolve_factorio() {
	want="${FACTORIO_VERSION:-}"
	if [ -n "${want}" ]; then
		url="https://factorio.com/get-download/${want}/headless/linux64"
	else
		url="https://factorio.com/get-download/latest/headless/linux64"
	fi
	final="$(curl -fsSL -A "$(games_ua)" -o /dev/null -w '%{url_effective}' "${url}")"
	VERSION="$(printf '%s\n' "${final}" | sed -n 's/.*factorio-headless_linux_\([0-9.]*\)\.tar.*/\1/p')"
	[ -n "${VERSION}" ] || {
		echo "could not parse factorio version from ${final}" >&2
		exit 1
	}
	printf '%s\n' "${VERSION}"
	printf '%s\n' "${url}"
}

# OpenTTD linux-generic release. Optional OPENTTD_VERSION. Prints: VERSION URL
games_resolve_openttd() {
	arch="$(games_arch_openttd)"
	OPENTTD_VERSION="${OPENTTD_VERSION:-}" OPENTTD_ARCH="${arch}" python3 <<'PY'
import json, os, sys, urllib.request

ua = {"User-Agent": "mvm-games/1.0"}
want = os.environ.get("OPENTTD_VERSION", "").strip()
arch = os.environ["OPENTTD_ARCH"]
if not want:
	rel = json.load(urllib.request.urlopen(urllib.request.Request(
		"https://api.github.com/repos/OpenTTD/OpenTTD/releases/latest", headers=ua)))
	want = rel["tag_name"]
url = f"https://cdn.openttd.org/openttd-releases/{want}/openttd-{want}-linux-generic-{arch}.tar.xz"
print(want)
print(url)
PY
}

# Latest OpenGFX baseset for OpenTTD. Prints: VERSION URL
games_resolve_opengfx() {
	python3 <<'PY'
import json, sys, urllib.request

ua = {"User-Agent": "mvm-games/1.0"}
rel = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://api.github.com/repos/OpenTTD/OpenGFX/releases/latest", headers=ua)))
tag = rel["tag_name"]
ver = tag.lstrip("v")
for asset in rel.get("assets", []):
	name = asset.get("name") or ""
	if name.endswith(".zip") and "opengfx" in name.lower():
		print(ver)
		print(asset["browser_download_url"])
		sys.exit(0)
# CDN fallback pattern
url = f"https://cdn.openttd.org/opengfx-releases/{ver}/opengfx-{ver}.zip"
print(ver)
print(url)
PY
}

games_ensure_gcompat() {
	if command -v gcompat >/dev/null 2>&1; then
		return 0
	fi
	if [ -f /etc/apk/repositories ]; then
		echo "installing gcompat for glibc game binaries"
		apk add --no-cache gcompat || true
	fi
}
