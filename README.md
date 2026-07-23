# Self-hosted services in Firecracker microVMs

Run self-hosted services in isolated Firecracker microVMs on your own server.

Each service gets its own lightweight VM, private network interface, and persistent data disk. The host only needs Firecracker, KVM, and root for networking.

## Why

- Strong isolation between services (separate kernel guests)
- Small attack surface compared with full VMs or containers
- Simple create, start, stop, update, and destroy lifecycle
- Templates stay generic with no hostnames, accounts, or secrets in the repo

## Requirements

- Linux with KVM (/dev/kvm readable)
- Firecracker on PATH
- curl, python3, tar, truncate, mkfs.ext4, ip, nft, dnsmasq
- conntrack optional for live flow listing
- Root for TAP networking and firewall policy
- Go optional, only to build the secrets CLI

## Install

One-liner (clones to ~/self-hosted-microvms, installs host packages, fetches Firecracker, runs setup when KVM is ready):

```bash
curl -fsSL https://raw.githubusercontent.com/Sudo-Ivan/self-hosted-microvms/master/install.sh | sh
```

Or from a checkout:

```bash
git clone https://github.com/Sudo-Ivan/self-hosted-microvms.git
cd self-hosted-microvms
sudo ./mvm deps
# optional: sudo ./mvm deps --with-go --with-shares
cp -n config.example.env config.env
./mvm setup
```

Supported package families: Ubuntu/Debian, Fedora/RHEL-like, Arch.

## Quick start

```bash
./mvm templates
./mvm info navidrome
sudo ./mvm up navi navidrome --profile media --share /home/user1/Music:/data/navidrome/music:ro
./mvm health navi
```

That up command runs setup if needed, creates the instance, starts it with root, applies Argus, waits until healthy, and prints the URL.

First boot installs packages inside the guest and can take a few minutes.

Handy template browse:

```bash
./mvm templates --tag=media
./mvm templates --tag=debug
./mvm info alpine-shell
sudo ./mvm up demo alpine-shell
```

## Common commands

| Command | Purpose |
| --- | --- |
| ./mvm doctor | Check host prerequisites |
| ./mvm deps | Install host packages and Firecracker |
| ./mvm setup | Fetch kernel and build base rootfs |
| ./mvm profiles | List resource profiles |
| ./mvm up name template | Create if needed, start, wait healthy |
| ./mvm templates | List templates (optional --tag=NAME) |
| ./mvm info template | Ports, tags, notes, example |
| ./mvm validate | Check template layout |
| ./mvm template new name | Scaffold a new service template |
| ./mvm template sync name | Copy latest template into a rootfs |
| ./mvm create name template | Create an instance only |
| ./mvm start name | Start instance, apply Argus and networking |
| ./mvm stop name | Stop instance and remove its TAP |
| ./mvm restart name | Stop then start |
| ./mvm resize name | Change mem/vcpu or grow disks |
| ./mvm list | Show instance state |
| ./mvm urls | Host and guest access URLs |
| ./mvm health | HTTP/HTTPS healthchecks |
| ./mvm logs name | Follow serial output |
| ./mvm update name | Upgrade guest packages (backs up first) |
| ./mvm rollback name | Restore latest backup |
| ./mvm backup name | Snapshot data and config |
| ./mvm restore name | Restore a backup stamp |
| ./mvm watchdog | Restart unhealthy guests |
| ./mvm tls name --domain host | Emit Caddy or nginx TLS snippets |
| ./mvm update --base | Rebuild shared base rootfs |
| ./mvm update --kernel | Fetch a newer guest kernel |
| ./mvm destroy name | Delete instance disks and config |
| ./mvm secrets | Encrypted host vault, injected at start |
| ./mvm service install | Install systemd/openrc/runit/dinit units |
| ./mvm service enable name | Enable autostart for an instance |
| ./mvm sudoers install | Passwordless sudo for mvm |
| ./mvm doas install | Passwordless doas for mvm |
| ./mvm argus apply | Apply firewall and DNS policy |
| ./mvm argus status | Per-VM policy, DNS, live connections |
| ./mvm argus queries | Recent guest DNS lookups |
| ./mvm argus watch | Follow connections and drops |
| ./mvm argus drops | Recent drop log lines |
| ./mvm argus dns-update | Refresh remote DNS blocklists |
| ./mvm argus flush | Remove Argus nftables table and DNS |

doas or sudo is required for start and stop with default TAP networking. Install passwordless access with doas ./mvm doas install or sudo ./mvm sudoers install. If both helpers exist, set MVM_ROOT_CMD to pick one.

Every start refreshes Argus when ARGUS_ENABLED=1.

Debug boot without networking:

```bash
sudo SETUP_NET=0 ./mvm start testshell
```

## Resource profiles

```bash
./mvm profiles
./mvm up media1 navidrome --profile media --share /path/to/music:/data/navidrome/music:ro
PROFILE=db ./mvm create pg postgres
```

Profiles live under profiles/ (small, default, media, db, proxy). Explicit --mem or --vcpu overrides the profile.

## Passwordless root (sudo or doas)

```bash
sudo ./mvm sudoers install
doas ./mvm doas install
sudo ./mvm sudoers install --user alice
doas ./mvm doas install --user alice
sudo ./mvm sudoers remove
doas ./mvm doas remove
```

sudoers writes /etc/sudoers.d/mvm. doas appends a managed block to /etc/doas.conf. Both install a /usr/local/sbin/mvm wrapper (needed when the repo path has spaces).

## Resize an instance

```bash
./mvm resize navi --mem 1024 --vcpu 2 --restart
./mvm resize navi --data-mib 8192 --restart
```

Memory and vCPU apply on next boot. Data and rootfs images only grow (never shrink) and need a stopped guest unless you pass --restart.

## Autostart (systemd, openrc, runit, dinit)

Unit templates live under init/. Install for your host init:

```bash
sudo ./mvm service install systemd
sudo ./mvm service enable navi
sudo systemctl enable --now mvm-watchdog
```

Other inits:

```bash
sudo ./mvm service install openrc
sudo ./mvm service install runit
sudo ./mvm service install dinit
sudo ./mvm service enable navi openrc
```

## Backups, update, rollback

```bash
./mvm backup navi
./mvm backup list navi
./mvm update navi
./mvm rollback navi
./mvm restore navi 20260722T120000Z
```

update takes a pre-update snapshot of data and rootfs. If health fails after update, run rollback.

## Watchdog

```bash
./mvm watchdog --once
sudo ./mvm watchdog
```

Restarts a guest after WATCHDOG_FAILURES consecutive health failures (config.env).

## TLS helper

Print or write host reverse-proxy snippets aimed at the instance port:

```bash
./mvm tls navi --domain music.example.com
./mvm tls navi --domain music.example.com --emit caddy --write
```

Writes under instances/name/tls/ when --write is set.

## Networking

Guests land on a private bridge (fcbr0 by default) under 10.100.0.0/24.

PORT_FORWARDS maps host ports to guest ports:

```bash
PORT_FORWARDS=8080:80 ./mvm create web nginx
PORT_FORWARDS=3000:3000,53:53:tcp,53:53:udp ./mvm create dns adguardhome
```

Format is host:guest or host:guest:tcp|udp. Multiple entries are comma separated.

## Host directory shares

Firecracker guests cannot bind-mount host paths directly. This toolkit exports host directories over NFS on the private bridge and mounts them in the guest.

```bash
HOST_SHARES='/home/user/Music:/data/navidrome/music:ro' \
  ./mvm create navi navidrome
sudo ./mvm start navi
```

Format is host_path:guest_path or host_path:guest_path:ro|rw. Multiple entries are comma separated.

Host needs nfs-utils (or nfs-kernel-server) so exportfs and nfs-server work.

## Argus central firewall and DNS

Argus (from Argos Panoptes, the all-seeing guardian) is the host-side control plane for guest traffic and DNS. Every microVM already exits through the host bridge, so a separate firewall VM is unnecessary for this design.

What Argus does:

- Isolates guests from each other by default
- Publishes only ports listed in PORT_FORWARDS
- Applies per-instance egress allow and deny lists
- Allows explicit guest-to-guest paths with ALLOW_PEERS
- Shows live connections attributed to instance names
- Logs denied packets with argus-drop prefixes
- Runs a gateway DNS resolver with remote and local blocklists
- Optionally forces all guest DNS through that resolver

Global policy:

```bash
cp argus/policy.example.env argus/policy.env
# edit ARGUS_DEFAULT_EGRESS, ARGUS_INTER_VM, and DNS options
sudo ./mvm argus apply
```

Per-instance policy in instances/name/firewall.env:

```bash
EGRESS_ALLOW=tcp/80,tcp/443
EGRESS_DENY=
ALLOW_PEERS=db
INGRESS_EXTRA=
```

DNS blocklists:

- Remote lists from ARGUS_DNS_BLOCKLIST_URLS (default StevenBlack hosts)
- Local lists in argus/blocklists/
- Never-block domains in argus/allowlist.txt
- Refresh with sudo ./mvm argus dns-update

Example tight setup:

1. Set ARGUS_DEFAULT_EGRESS=deny and ARGUS_INTER_VM=deny in argus/policy.env
2. Give app VMs only the outbound ports they need
3. Let web reach vault and forgejo with ALLOW_PEERS=vault,forgejo
4. Keep databases with empty egress and no peers
5. Keep ARGUS_DNS_FORCE=1 so lookups hit the blocklists

Commands:

```bash
sudo ./mvm argus apply
./mvm argus status
sudo ./mvm argus status vault
./mvm argus queries navi
sudo ./mvm argus watch
sudo ./mvm argus drops
sudo ./mvm argus dns-update
```

Start and stop refresh Argus automatically when ARGUS_ENABLED=1.

## Persistence and updates

Each instance has:

- rootfs.ext4 operating system disk
- data.ext4 service data disk mounted at /data

Rebuild or upgrade the OS disk without throwing away application state on /data.

Update paths:

1. Guest packages: ./mvm update name
2. Shared base image: ./mvm update --base
3. Kernel: ./mvm update --kernel
4. Template software pins: edit template install scripts, recreate the instance, keep the old data.ext4 if you migrate it manually

## Secrets (host vault)

Store secrets encrypted on the host. At start (or restart) they are injected into that guest only through Firecracker MMDS, then landed on tmpfs as /run/secrets/env.

```bash
./scripts/build-mvmsec.sh
./mvm secrets init
./mvm secrets set navi NAVIDROME_PASSWORD='...'
doas ./mvm start navi
```

init tries to seal the age identity to the TPM when /dev/tpmrm0 or /dev/tpm0 is usable. That binds decryption to this machine. Options:

- --passphrase wraps the identity with a passphrase
- --tpm requires TPM (fails if missing)
- --passphrase --tpm uses TPM plus a passphrase backup
- --no-tpm keeps a mode-600 identity file on disk

Check protection with ./mvm secrets protect status.

For passphrase-protected stores under a service manager, set MVM_SECRETS_PASSPHRASE or MVM_SECRETS_PASSPHRASE_FILE before start.

Templates that consume injected secrets should include curl in PACKAGES. Guest-generated keys on /data remain valid for templates that create them on first boot. Keep secrets out of the template tree and out of config.env.

## Templates included

- vaultwarden password manager API
- jellyfin media server
- forgejo Git forge
- caddy reverse proxy
- nginx web server
- adguardhome DNS ad blocking
- syncthing file sync
- navidrome music server
- minio S3-compatible storage
- redis key value store
- postgres database
- transmission BitTorrent client
- grafana dashboards
- uptime-kuma uptime monitoring
- filebrowser web file manager
- ntfy push notifications over HTTP
- gotify self-hosted push notification server
- memos lightweight notes
- homebox home inventory
- pocketbase backend as a single binary
- silverbullet markdown PKM
- vikunja to-do app
- meilisearch search API
- stirling-pdf PDF toolkit
- headscale open-source Tailscale control server
- qbittorrent BitTorrent client with Web UI
- it-tools handy web tools for developers
- beszel lightweight server monitoring hub
- kavita ebook and comic server
- writefreely minimalist blogging
- prometheus metrics and time series DB
- copyparty portable file server
- gitea self-hosted Git service
- searxng privacy-respecting metasearch
- reticulum Reticulum Network Stack daemon (rnsd)
- reticulum-go Reticulum-Go daemon
- nomadnet Nomad Network daemon on Reticulum
- meshchatx MeshChatX headless web client for Reticulum
- alpine-shell minimal idle guest for debugging

## Adding a template

Create templates/name/ with:

- manifest.env resources, ports, PACKAGES, and TAGS
- install.sh first-boot provisioning (pin upstream with VERSION or CHANNEL vars)
- run.sh service entrypoint (PID 1 child)

Optional manifest fields: DATA_HINT, NOTES, HEALTH_SCHEME, HEALTH_WAIT_SECS.

Scaffold and validate:

```bash
./mvm template new myapp --port 8080 --tag tools --desc "My service"
# edit templates/myapp/install.sh and run.sh
./mvm validate
./mvm info myapp
```

Update a running instance after template edits:

```bash
./mvm template sync myappdemo --restart
./mvm update myappdemo
```

Put durable state under /data.

## Guest hardening

By default each guest drops to a non-root svc user via setpriv before run.sh and keeps only CAP_NET_BIND_SERVICE (for ports like 80/443/53). Optional bubblewrap mode makes the root filesystem read-only and only /data and /run writable.

Set in the template manifest.env:

```bash
HARDEN=setpriv
# HARDEN=bwrap
# HARDEN=off
# HARDEN_USER=svc
```

alpine-shell uses HARDEN=off for debugging. First boot installs util-linux (and bubblewrap when HARDEN=bwrap). Existing instances pick this up on the next privileged start (template sync) then restart.

## Security notes

- Guests are isolated VMs, not a substitute for app hardening
- Guests drop to a non-root service user by default (HARDEN=setpriv)
- Default templates bind services on the guest network interface
- Prefer putting public exposure behind your own reverse proxy and TLS
- Change default credentials on first login
- Do not commit config.env, shared/, or instances/
- Do not commit shared/secrets/ identity or vault files

## License

[0BSD](LICENSE)
