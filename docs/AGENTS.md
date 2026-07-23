# AGENTS.md

Guidance for LLMs and coding agents working in this repository.

## What this project is

Self-hosted Firecracker microVM toolkit. The CLI entrypoint is `./mvm`.
Each service runs in its own Alpine-based guest VM with:

- a root filesystem image (`instances/<name>/rootfs.ext4`)
- a durable data disk (`instances/<name>/data.ext4`)
- a TAP NIC on a private bridge
- host port forwards and firewall policy via Argus

Do not treat guests like Docker containers. They are real VMs with a kernel,
init, and disk images.

## Firecracker model (how it works here)

1. Host prepares assets under `shared/` (kernel `vmlinux`, Alpine base staging).
2. `./mvm create` clones base staging, copies `templates/<template>/` into
   guest `/opt/template`, builds `rootfs.ext4` and empty `data.ext4`, writes
   `instances/<name>/config.env`.
3. `./mvm start` (needs root) creates TAP, applies Argus, regenerates
   `vm-config.json`, launches Firecracker with API socket
   `instances/<name>/firecracker.sock`.
4. Guest PID 1 is `guest/init`. First boot runs `guest/first-boot.sh` which
   installs `PACKAGES` and runs `/opt/template/install.sh`. Then
   `guest/run-service.sh` prepares hardening and execs `/opt/template/run.sh`
   via `guest/harden-exec.sh` (non-root setpriv by default, optional bwrap).
5. Service state must live on `/data` (the second virtio disk). Rootfs can be
   rebuilt; data should survive updates when done correctly.

Machine size (mem, vCPU) is read from `config.env` at start and baked into
`vm-config.json`. Changing those values requires a restart. Disk growth is
offline (`truncate` + `resize2fs`).

## Repo layout

- `mvm` dispatcher
- `cmd/mvmsec/` age-encrypted host secrets CLI
- `scripts/` host lifecycle tools
- `lib/` shared POSIX sh helpers (`common.sh`, `network.sh`, `guestfs.sh`, ...)
- `guest/` guest init and boot hooks copied into each rootfs
- `templates/<name>/` service templates
- `templates/_common/` shared guest helpers (download/arch)
- `argus/` central nftables + dnsmasq DNS policy
- `profiles/` resource presets (small/default/media/db/proxy)
- `instances/` local runtime (gitignored)
- `shared/` local kernel/base/backups/secrets (gitignored)
- `docs/INSTRUCTIONS.md` human operator guide

## Privilege model (sudo and doas)

Networking, TAP, nftables, loop mounts, and Firecracker start/stop need root.

Helpers:

- `root_helper` / `run_as_root` in `lib/common.sh`
- prefers `MVM_ROOT_CMD`, then `doas`, then `sudo`
- passwordless installers:
  - `./mvm sudoers install|remove`
  - `./mvm doas install|remove`

When editing messages or docs, mention both doas and sudo.
Do not hardcode only `sudo` in new scripts. Use `run_as_root` / `root_helper`.

## Argus

Argus is the host-side guardian for guest traffic:

- nftables table for egress, inter-VM, NAT, port forwards
- optional forced DNS via dnsmasq + blocklists
- global knobs: `argus/policy.env` (from defaults in repo)
- per-instance knobs: `instances/<name>/firewall.env`
  (seeded from template `firewall.env` or `argus/firewall.example.env`)

Commands:

- `./mvm argus apply`
- `./mvm argus status [name]`
- `./mvm argus watch|drops|queries|dns-update|flush`

Start/stop refresh Argus when enabled. After editing firewall files, apply again.

## Templates

Each template directory (except `_common`) needs:

- `manifest.env` DESCRIPTION, MEM_MIB, VCPU_COUNT, PORT_FORWARDS, PACKAGES, TAGS
- `install.sh` first-boot provisioning (pin upstream with `*_VERSION` or `*_CHANNEL`)
- `run.sh` foreground process (the guest service)

Optional:

- `update.sh` called by guest update path (`./mvm update`)
- `firewall.env` Argus defaults
- `config.example` app config copied to `/data` on first run
- `DATA_HINT`, `NOTES`, `HEALTH_SCHEME`, `HEALTH_WAIT_SECS` in manifest

Rules:

- No hostnames, emails, public IPs, or real secrets in templates
- Durable state under `/data/...`
- Prefer official release binaries or Alpine packages
- Keep `run.sh` simple and foregrounded

Authoring commands:

- `./mvm template new <name> --port N --tag TAG --desc "..."`
- edit install/run, pin version
- `./mvm validate`
- `./mvm info <name>`
- `./mvm up demo <name>`

Updating an existing instance after template edits:

1. Change template files (usually bump `*_VERSION` in `install.sh`).
2. Ensure `update.sh` re-runs install when package contents must change.
3. `./mvm template sync <instance>` (also happens automatically on privileged start).
4. `./mvm update <instance>` to run guest package/template update path.
5. Or destroy/recreate if first-boot only logic must rerun cleanly.

Validate with `./mvm validate` before finishing template work.

## Resize

```sh
./mvm resize <name> --mem 1024 --vcpu 2 --data-mib 8192 --restart
```

- mem/vcpu: update `config.env`, apply on next boot (`--restart` to bounce)
- data/rootfs: grow only, guest must be stopped (or pass `--restart`)
- never shrink disks

## Common agent workflows

Add a service template:

1. Prefer `./mvm template new ...` over copying by hand.
2. Replace example download URL and pin version.
3. Implement real `run.sh`.
4. Add TAGS/NOTES/HEALTH_* as needed.
5. Run `./mvm validate`.
6. Update README template list only if the project already maintains one.

Fix a guest service:

1. Check `./mvm logs <name>` and instance `config.env`.
2. Reproduce with health/urls.
3. Patch template under `templates/<name>/`.
4. Sync + update, or recreate if install is broken mid-first-boot.

Touch networking/firewall:

1. Read `argus/lib.sh` and instance `firewall.env`.
2. Keep inter-VM default deny unless there is a clear peer need.
3. Re-apply with `./mvm argus apply`.

## Secrets

Host vault lives under `shared/secrets/` (age encrypted, gitignored).

1. `./scripts/build-mvmsec.sh` then `./mvm secrets init`
2. Prefer TPM seal when the host has `/dev/tpmrm0` or `/dev/tpm0` (default try). Use `--passphrase` and/or `--tpm` / `--no-tpm` as needed
3. `./mvm secrets set <instance> KEY=value` (list shows key names only)
4. `./mvm start <instance>` injects that instance only via MMDS V2
5. Guest writes `/run/secrets/env` and `run-service.sh` exports it before `run.sh`
6. Never commit identity, vault, or passphrase files. Never put secrets in templates or `config.env`

For passphrase-only unlock in non-interactive start, set `MVM_SECRETS_PASSPHRASE` or `MVM_SECRETS_PASSPHRASE_FILE`.

Templates that use injected secrets should include `curl` in `PACKAGES`.

Guest hardening defaults to non-root `setpriv` (`HARDEN=setpriv` in manifest, or `bwrap` / `off`).

## Local files you must not commit

Ignored by `.gitignore`:

- `config.env`
- `shared/**` (includes `shared/secrets/`)
- `instances/**`
- local secrets, sockets, logs, editor junk

Never commit live credentials from `/data` volumes or generated admin passwords.

## Style constraints for this repo

- Host tools are POSIX `sh` (`#!/bin/sh`, `set -eu`). Not bash.
- Avoid bashisms: no `[[ ]]`, arrays, `local`, `pipefail`, `$''`, process
  substitution, or `source` (use `.`)
- Prefer `shellcheck -s sh` on changed scripts
- Match existing script headers and helpers in `lib/common.sh`
- No emojis in code or docs
- No TODO spam
- No semicolons in comments
- Do not invent markdown docs unless the user asks (AGENTS.md and README updates
  requested by maintainers are fine)
- Prefer small focused changes over broad refactors

## Quick command map

- doctor/setup: host readiness and shared assets
- up/create/start/stop/restart/destroy: instance lifecycle
- templates/info/validate/template new|sync: template UX
- resize: mem/vcpu/disk growth
- update/backup/restore/rollback: maintenance
- secrets: age vault and MMDS inject at start
- argus *: firewall/DNS
- sudoers/doas: passwordless root helpers
- service *: host init autostart units
