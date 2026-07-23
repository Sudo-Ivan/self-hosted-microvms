# Operator instructions

This guide is for humans running the toolkit on a Linux server with Firecracker already installed.

## 1. One-time host prep

1. Confirm KVM is usable:

```bash
ls -l /dev/kvm
```

Your user should be able to read and write it, usually through the `kvm` group.

2. Confirm Firecracker:

```bash
firecracker --version
```

3. Install basic host tools if any are missing:

- curl
- python3
- tar
- truncate
- mkfs.ext4
- iproute2 (`ip`)
- nftables (`nft`)
- dnsmasq (for Argus DNS blocklists)
- conntrack-tools (`conntrack`) optional for live flow listing

4. Copy the example config:

```bash
cp config.example.env config.env
```

Edit only what you need. Keep secrets out of this file.

Useful knobs:

- `BRIDGE_NAME` private bridge name
- `SUBNET_PREFIX` first three octets of the guest network
- `ALPINE_VERSION` and `ALPINE_RELEASE` base image pins
- `KERNEL_SERIES` preferred guest kernel series
- `ARGUS_ENABLED` central firewall and DNS on or off

## 2. Build shared assets

From the repo root:

```bash
./mvm setup
```

This downloads a Firecracker CI guest kernel and builds an Alpine-based rootfs staging tree under `shared/`.

To force a clean rebuild later:

```bash
./mvm setup --rebuild
```

## 3. Pick a template

```bash
./mvm templates
```

Choose a service name from the list. Templates are intentionally generic.

## 4. Create an instance

```bash
./mvm create myvault vaultwarden
```

Optional overrides:

```bash
MEM_MIB=1024 \
VCPU_COUNT=2 \
PORT_FORWARDS=8443:80 \
DATA_SIZE_MIB=4096 \
./mvm create myvault vaultwarden
```

Create writes:

- `instances/<name>/config.env`
- `instances/<name>/rootfs.ext4`
- `instances/<name>/data.ext4`

You can edit `instances/<name>/config.env` before the first start if you need different ports or memory.

## 5. Start and stop

Start needs root for TAP devices and port forwards:

```bash
sudo ./mvm start myvault
```

Check state:

```bash
./mvm list
```

Follow guest serial logs:

```bash
./mvm logs myvault
```

Stop:

```bash
sudo ./mvm stop myvault
```

Stop everything:

```bash
sudo ./mvm stop --all
```

## 6. First boot behavior

On the first boot the guest will:

1. Bring up `eth0` using values from `/etc/microvm-net`
2. Mount `/dev/vdb` on `/data`
3. Run `apk update` and install template packages
4. Run the template `install.sh`
5. Start the template `run.sh`

First boot needs outbound network access from the guest so package and release downloads work.

If install fails, read the serial log, fix the template or network, destroy the instance, and create it again. The data disk is removed by destroy, so copy out anything you care about first.

## 7. Day-two updates

Guest OS packages:

```bash
sudo ./mvm update myvault
```

Shared base rootfs used by new instances:

```bash
./mvm update --base
```

Guest kernel used by all instances on next start:

```bash
./mvm update --kernel
```

Application version pins live in each template `install.sh`. Bump the version variable, then recreate the instance and reuse data carefully:

1. Stop the instance
2. Copy `instances/<name>/data.ext4` somewhere safe
3. Destroy the instance
4. Create a new instance from the updated template
5. Stop it before first boot if you need to replace `data.ext4` with the saved volume
6. Start it again

For many services, keeping the same `data.ext4` is enough because app state lives under `/data`.

## 8. Networking model

Default layout:

- Bridge: `fcbr0`
- Gateway: `10.100.0.1`
- Guests: `10.100.0.10`, `10.100.0.11`, ...

Port forwards example:

```bash
PORT_FORWARDS=8080:80,8443:443
```

Protocol-specific example:

```bash
PORT_FORWARDS=53:53:udp,53:53:tcp,3000:3000
```

From the host you can also reach the guest IP directly on the bridge, for example `http://10.100.0.10/`.

## 9. Argus central firewall and DNS

Argus is the custom host firewall and DNS control plane for this project. The name comes from Argos Panoptes, the all-seeing guardian. It sits on the shared bridge and controls every guest path.

Why host-side instead of a firewall microVM:

- All guests already route through the host
- Policy changes do not require another VM to stay healthy
- Visibility and enforcement stay in one place

Global defaults live in `argus/policy.env` (created from the example by `./mvm setup`).

Important knobs:

- `ARGUS_DEFAULT_EGRESS=allow|deny` outbound internet default
- `ARGUS_INTER_VM=deny|allow` guest-to-guest default
- `ARGUS_LOG_DROPS=1` log denied packets
- `ARGUS_DNS_ENABLED=1` gateway DNS resolver
- `ARGUS_DNS_FORCE=1` redirect guest DNS to the gateway
- `ARGUS_DNS_BLOCKLIST_URLS` remote blocklist sources

Per-instance rules live in `instances/<name>/firewall.env`:

```bash
EGRESS_ALLOW=tcp/80,tcp/443
EGRESS_DENY=
ALLOW_PEERS=db
INGRESS_EXTRA=
```

`PORT_FORWARDS` automatically become ingress allows and DNAT rules.

DNS blocklists:

1. Remote lists are cached under `shared/argus-dns/cache/`
2. Local lists live in `argus/blocklists/*.list`
3. Domains in `argus/allowlist.txt` are never blocked
4. Refresh remote lists with `sudo ./mvm argus dns-update`

Typical app plus database layout:

1. Create `db` from `postgres` and `app` from your app template
2. In `instances/app/firewall.env` set `ALLOW_PEERS=db`
3. Set `ARGUS_DEFAULT_EGRESS=deny` if you want allow-lists only
4. Apply:

```bash
sudo ./mvm argus apply
sudo ./mvm argus status
sudo ./mvm argus watch
sudo ./mvm argus drops
```

Start and stop refresh Argus when it is enabled. After you edit a `firewall.env` or blocklist, run `sudo ./mvm argus apply` or `sudo ./mvm argus dns-update`.

## 10. Where data and secrets live

- Put durable service state under `/data` inside the guest
- Do not put passwords, tokens, or host-specific names into templates committed to git

### Host vault (recommended for injected secrets)

Build the CLI once, then store secrets encrypted under `shared/secrets/` (gitignored):

```bash
./scripts/build-mvmsec.sh
./mvm secrets init
./mvm secrets set navi NAVIDROME_PASSWORD='...'
```

`init` tries to seal the age identity to the TPM when `/dev/tpmrm0` or `/dev/tpm0` is usable. That binds decryption to this machine without systemd. Options:

```bash
./mvm secrets init --passphrase          # wrap identity with a passphrase
./mvm secrets init --tpm                 # require TPM (fail if missing)
./mvm secrets init --passphrase --tpm    # TPM primary plus passphrase backup
./mvm secrets init --no-tpm              # plaintext identity file (mode 600)
./mvm secrets protect status
```

Passphrase unlock for non-interactive start (service units):

```bash
export MVM_SECRETS_PASSPHRASE='...'
# or
export MVM_SECRETS_PASSPHRASE_FILE=/root/.mvm-secrets-passphrase
```

On `./mvm start` / restart the host decrypts only that instance and pushes values into Firecracker MMDS V2. The guest writes them to `/run/secrets/env` (tmpfs) and `run-service.sh` exports them before `run.sh`. Values are not written to `/data` by default.

Requirements:

- Guest template `PACKAGES` should include `curl` so MMDS fetch works
- Networking must be enabled (`SETUP_NET=1`) because MMDS uses `eth0`
- Restart the instance after changing secrets so they are re-injected

Useful commands:

```bash
./mvm secrets list
./mvm secrets list navi
./mvm secrets unset navi NAVIDROME_PASSWORD
./mvm secrets exists navi
```

### Guest hardening

By default run-service drops to user svc with setpriv before run.sh and keeps CAP_NET_BIND_SERVICE only. Optional HARDEN=bwrap also makes the guest root filesystem read-only (writable /data and /run).

In template manifest.env:

```bash
HARDEN=setpriv
# HARDEN=bwrap
# HARDEN=off
```

alpine-shell uses HARDEN=off. Sync and restart existing instances to pick up the new guest scripts.

### Guest-generated or operator files on `/data`

Some templates still create or expect files on the data volume:

- Vaultwarden admin token file: `/data/vaultwarden/admin.token`
- MinIO generated keys: `/data/minio/root-user` and `/data/minio/root-password`
- Grafana admin env file: `/data/grafana/admin.env`
- Caddy site config: `/data/caddy/Caddyfile`

## 11. Adding your own template

Scaffold:

```bash
./mvm template new myapp --port 8080 --tag tools --desc "Short summary"
```

Or create `templates/myapp/` by hand with:

`manifest.env`:

```bash
DESCRIPTION="Short summary"
MEM_MIB=512
VCPU_COUNT=1
DATA_SIZE_MIB=2048
ROOTFS_SIZE_MIB=1024
PORT_FORWARDS=8080:8080
PACKAGES="ca-certificates curl"
TAGS=misc
```

`install.sh`:

- Download or apk-install the app
- Pin upstream with a `*_VERSION` variable
- Write default config under `/data/...` only when missing

`run.sh`:

- Start the process in the foreground
- Read configuration from `/data`

Optional `update.sh` should re-run install so `./mvm update` picks up version bumps.

Make the scripts executable. Then:

```bash
./mvm validate
./mvm create demo myapp
doas ./mvm start demo
# or: sudo ./mvm start demo
```

After editing a template used by an existing instance:

```bash
./mvm template sync demo --restart
./mvm update demo
```

Shared download helpers are available at `/opt/template/_common/download.sh` inside the guest during install.

## 11b. Resize an instance

```bash
./mvm resize myvault --mem 1024 --vcpu 2 --restart
./mvm resize myvault --data-mib 8192 --restart
```

Memory and vCPU apply on next boot. Disk images only grow and need a stopped guest unless `--restart` is set.

## 12. Maintenance tips

- Keep `shared/` and `instances/` on fast local disk
- Back up `instances/<name>/data.ext4` regularly
- Recreate instances from templates instead of hand-editing rootfs when possible
- Use `alpine-shell` when you need a throwaway guest for network checks
- Review `iptables` rules if port forwards behave unexpectedly after crashes

## 13. Removing an instance

```bash
sudo ./mvm destroy myvault
```

You will be asked to type the instance name. Add `--yes` only when scripting.

## 14. Public repo hygiene

Safe to publish:

- scripts, guest files, templates, docs, example config

Keep private:

- `config.env`
- `shared/`
- `instances/`
- any copied data volumes

Before publishing, search templates for hostnames, emails, domains, tokens, and personal paths.
