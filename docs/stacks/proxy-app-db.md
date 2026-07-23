# Stack: proxy to app to database

Worked Argus example with three guests:

- `edge` from `caddy` (public reverse proxy)
- `app` from `forgejo` (application)
- `db` from `postgres` (database)

Traffic path: internet -> host ports on `edge` -> bridge to `app` -> bridge to `db`.

## 1. Global policy

In `argus/policy.env` (copy from `argus/policy.example.env` if needed):

```bash
ARGUS_DEFAULT_EGRESS=deny
ARGUS_INTER_VM=deny
ARGUS_DNS_FORCE=1
```

Apply after edits:

```bash
./mvm argus apply
```

With passwordless doas/sudoers installed, `./mvm` elevates automatically for start, stop, and Argus.

## 2. Create the three guests

```bash
PROFILE=db ./mvm create db postgres
./mvm create app forgejo
PROFILE=proxy ./mvm create edge caddy
```

Or one-shot:

```bash
./mvm up db postgres --profile db
./mvm up app forgejo
./mvm up edge caddy --profile proxy
```

Use your own instance names if you prefer. Peer names in firewall files must match.

## 3. Firewall files

### `instances/db/firewall.env`

```bash
EGRESS_ALLOW=
EGRESS_DENY=
ALLOW_PEERS=
INGRESS_EXTRA=
```

Database stays dark: no internet egress, no peer list. Only guests that list `db` in `ALLOW_PEERS` can reach it.

### `instances/app/firewall.env`

```bash
EGRESS_ALLOW=tcp/22,tcp/80,tcp/443
EGRESS_DENY=
ALLOW_PEERS=db
INGRESS_EXTRA=
```

App may talk to `db` on the bridge and make outbound HTTPS/SSH for mirrors or webhooks.

### `instances/edge/firewall.env`

```bash
EGRESS_ALLOW=tcp/80,tcp/443
EGRESS_DENY=
ALLOW_PEERS=app
INGRESS_EXTRA=
```

Proxy may reach `app` and talk to the internet for ACME and clients.

Then:

```bash
./mvm argus apply
./mvm argus status
```

## 4. Publish the app through the proxy

```bash
./mvm publish app --domain git.example.com --via edge --restart-via
./mvm argus apply
```

That writes a Caddy site drop-in on the edge data volume (`/data/caddy/sites/app.caddy`), adds `app` to edge `ALLOW_PEERS` if needed, and restarts edge when it was running.

Host-only snippets (no proxy guest):

```bash
./mvm publish app --domain git.example.com --emit caddy --write
```

## 5. Verify

```bash
./mvm list
./mvm health app
./mvm urls edge
./mvm argus status edge
./mvm argus queries app
```

From the host, open the published domain aimed at edge port 80/443 (see `./mvm urls edge`).

## Notes

- Peer allow is instance-name based (`ALLOW_PEERS=db`), not port-scoped.
- Disks only grow (`./mvm resize`). To copy a guest, use `./mvm clone src dst`.
- Whole-VM rollback: `./mvm snapshot app before-change` then `./mvm restore app <stamp>`.
- Secrets for the app are not shared automatically: `./mvm secrets set app KEY=...`.
