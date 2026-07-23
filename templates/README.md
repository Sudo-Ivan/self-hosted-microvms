# Templates

Each directory is one service template (except `_common`).

Required files:

- `manifest.env` resource defaults, ports, packages, tags
- `install.sh` first-boot setup
- `run.sh` foreground process

Optional:

- `update.sh` re-run on `./mvm update` (usually calls `install.sh`)
- `firewall.env` Argus defaults
- `config.example` first-run app config
- `TAGS`, `DATA_HINT`, `NOTES`, `HEALTH_SCHEME`, `HEALTH_WAIT_SECS` in manifest

## Scaffold a new template

```bash
./mvm template new myapp --port 8080 --tag tools --desc "My service"
```

Then edit `install.sh` (real URL + version pin) and `run.sh`.

## Update an existing instance

Host start already refreshes `/opt/template` from the repo when run as root.
For an explicit sync:

```bash
./mvm template sync <instance> --restart
./mvm update <instance>
```

Bump `*_VERSION` in `install.sh` before update when the binary/package changed.

## Guidelines

- Store durable state under `/data`
- Do not hardcode hostnames, public IPs, emails, or secrets
- Pin upstream versions with variables at the top of `install.sh`
- Prefer official release binaries or Alpine packages
- Keep `run.sh` simple and foregrounded (it is the guest service process)

## Validate

```bash
./mvm validate
./mvm templates --tag=media
./mvm info navidrome
```
