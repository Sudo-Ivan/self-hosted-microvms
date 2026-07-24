# Shared Minecraft helpers for template install/run scripts.
# Source after set -eu. Requires python3 and curl.

minecraft_ua() {
	printf '%s\n' "mvm-minecraft/1.0"
}

minecraft_arch_adoptium() {
	machine="$(uname -m)"
	case "${machine}" in
	x86_64) echo x64 ;;
	aarch64|arm64) echo aarch64 ;;
	*)
		echo "unsupported arch for Temurin: ${machine}" >&2
		exit 1
		;;
	esac
}

# Print recommended Java major for a Minecraft version id.
minecraft_java_major() {
	ver="$1"
	python3 - "$ver" <<'PY'
import sys
ver = sys.argv[1]
parts = ver.split(".")
try:
	major = int(parts[0])
except ValueError:
	major = 0
# Mojang/Paper year-style ids (26.x) need Java 25+.
if major >= 26:
	print(25)
	sys.exit(0)
if len(parts) >= 2:
	try:
		minor = int(parts[1])
	except ValueError:
		minor = 0
	if major == 1 and minor >= 20:
		print(21)
		sys.exit(0)
	if major == 1 and minor >= 17:
		print(17)
		sys.exit(0)
	if major == 1 and minor >= 12:
		print(11)
		sys.exit(0)
print(21)
PY
}

# Install Temurin JRE for MAJOR into /opt/java (dynamic Adoptium latest GA).
minecraft_install_java() {
	major="$1"
	arch="$(minecraft_arch_adoptium)"
	url="https://api.adoptium.net/v3/binary/latest/${major}/ga/linux/${arch}/jre/hotspot/normal/eclipse?project=jdk"
	echo "installing Temurin JRE ${major} (${arch})"
	rm -rf /opt/java
	mkdir -p /opt/java /tmp/mc-java
	curl -fL -A "$(minecraft_ua)" -o /tmp/mc-java/jre.tgz "${url}"
	tar -xzf /tmp/mc-java/jre.tgz -C /tmp/mc-java
	inner="$(find /tmp/mc-java -mindepth 1 -maxdepth 1 -type d | head -n1)"
	[ -n "${inner}" ] || {
		echo "temurin extract failed" >&2
		exit 1
	}
	cp -a "${inner}/." /opt/java/
	rm -rf /tmp/mc-java
	[ -x /opt/java/bin/java ] || {
		echo "java missing after Temurin install" >&2
		exit 1
	}
	/opt/java/bin/java -version
}

# Resolve vanilla server jar. Override with MC_VERSION. Prints: VERSION URL
minecraft_resolve_vanilla() {
	want="${1:-}"
	MC_VERSION="${want}" python3 <<'PY'
import json, os, sys, urllib.request

ua = {"User-Agent": "mvm-minecraft/1.0"}
want = os.environ.get("MC_VERSION", "").strip()
manifest = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://launchermeta.mojang.com/mc/game/version_manifest_v2.json", headers=ua)))
if not want:
	want = manifest["latest"]["release"]
meta_url = None
for entry in manifest["versions"]:
	if entry["id"] == want:
		meta_url = entry["url"]
		break
if not meta_url:
	sys.stderr.write(f"vanilla version not found: {want}\n")
	sys.exit(1)
meta = json.load(urllib.request.urlopen(urllib.request.Request(meta_url, headers=ua)))
server = meta.get("downloads", {}).get("server")
if not server or "url" not in server:
	sys.stderr.write(f"no server jar for {want}\n")
	sys.exit(1)
print(want)
print(server["url"])
PY
}

# Resolve Paper jar via Fill v3. Override with MC_VERSION. Prints: VERSION BUILD URL
minecraft_resolve_paper() {
	want="${1:-}"
	MC_VERSION="${want}" python3 <<'PY'
import json, os, sys, urllib.request

ua = {"User-Agent": "mvm-minecraft/1.0"}
want = os.environ.get("MC_VERSION", "").strip()
proj = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://fill.papermc.io/v3/projects/paper", headers=ua)))
versions = []
for group, items in proj.get("versions", {}).items():
	for item in items:
		versions.append(item)
if not versions:
	sys.stderr.write("paper: no versions from fill API\n")
	sys.exit(1)
if not want:
	want = versions[0]
elif want not in versions:
	sys.stderr.write(f"paper version not found: {want}\n")
	sys.exit(1)
builds = json.load(urllib.request.urlopen(urllib.request.Request(
	f"https://fill.papermc.io/v3/projects/paper/versions/{want}/builds", headers=ua)))
if not builds:
	sys.stderr.write(f"paper: no builds for {want}\n")
	sys.exit(1)
preferred = [b for b in builds if b.get("channel") == "STABLE"]
if not preferred:
	preferred = [b for b in builds if b.get("channel") == "RECOMMENDED"]
if not preferred:
	preferred = builds
build = preferred[0]
dl = build.get("downloads", {}).get("server:default")
if not dl or "url" not in dl:
	sys.stderr.write(f"paper: missing download for {want} build {build.get('id')}\n")
	sys.exit(1)
print(want)
print(build["id"])
print(dl["url"])
PY
}

# Resolve Fabric server jar. Override with MC_VERSION / FABRIC_LOADER / FABRIC_INSTALLER.
# Prints: GAME LOADER INSTALLER URL
minecraft_resolve_fabric() {
	want="${1:-}"
	MC_VERSION="${want}" FABRIC_LOADER="${FABRIC_LOADER:-}" FABRIC_INSTALLER="${FABRIC_INSTALLER:-}" python3 <<'PY'
import json, os, sys, urllib.request

ua = {"User-Agent": "mvm-minecraft/1.0"}
want = os.environ.get("MC_VERSION", "").strip()
loader_want = os.environ.get("FABRIC_LOADER", "").strip()
installer_want = os.environ.get("FABRIC_INSTALLER", "").strip()

games = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://meta.fabricmc.net/v2/versions/game", headers=ua)))
if not want:
	stable = [g["version"] for g in games if g.get("stable")]
	if not stable:
		sys.stderr.write("fabric: no stable game versions\n")
		sys.exit(1)
	want = stable[0]
else:
	ids = {g["version"] for g in games}
	if want not in ids:
		sys.stderr.write(f"fabric game version not found: {want}\n")
		sys.exit(1)

loaders = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://meta.fabricmc.net/v2/versions/loader", headers=ua)))
if loader_want:
	loader = loader_want
else:
	stable = [l["version"] for l in loaders if l.get("stable")]
	loader = stable[0] if stable else loaders[0]["version"]

installers = json.load(urllib.request.urlopen(urllib.request.Request(
	"https://meta.fabricmc.net/v2/versions/installer", headers=ua)))
if installer_want:
	installer = installer_want
else:
	stable = [i["version"] for i in installers if i.get("stable")]
	installer = stable[0] if stable else installers[0]["version"]

url = f"https://meta.fabricmc.net/v2/versions/loader/{want}/{loader}/{installer}/server/jar"
print(want)
print(loader)
print(installer)
print(url)
PY
}

minecraft_download() {
	url="$1"
	dest="$2"
	tmpdir="$(dirname "${dest}")"
	mkdir -p "${tmpdir}"
	echo "downloading ${url}"
	curl -fL -A "$(minecraft_ua)" --progress-bar -o "${dest}.partial" "${url}"
	mv -f "${dest}.partial" "${dest}"
}

minecraft_prepare_data() {
	mkdir -p /data/minecraft/world /data/minecraft/logs /data/minecraft/mods /data/minecraft/plugins
	if [ ! -f /data/minecraft/eula.txt ]; then
		printf 'eula=true\n' >/data/minecraft/eula.txt
		echo "accepted Minecraft EULA in /data/minecraft/eula.txt"
	fi
	if [ ! -f /data/minecraft/server.properties ]; then
		cat >/data/minecraft/server.properties <<'EOF'
# Generated by mvm minecraft template. Edit on the data volume.
motd=A Minecraft Server
server-port=25565
online-mode=true
max-players=20
view-distance=10
spawn-protection=16
EOF
	fi
}

minecraft_run_jar() {
	jar="$1"
	[ -x /opt/java/bin/java ] || {
		echo "missing /opt/java/bin/java" >&2
		exit 1
	}
	[ -f "${jar}" ] || {
		echo "missing server jar: ${jar}" >&2
		exit 1
	}
	minecraft_prepare_data
	cd /data/minecraft || exit 1
	xms="${MC_XMS:-512M}"
	xmx="${MC_XMX:-1536M}"
	echo "starting ${jar} Xms=${xms} Xmx=${xmx}"
	exec /opt/java/bin/java -Xms"${xms}" -Xmx"${xmx}" -jar "${jar}" nogui
}
