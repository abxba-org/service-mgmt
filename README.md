# service-mgmt

Shell-based service management helpers for Tailscale exposure workflows.

## `tailscale-services`

Production-oriented, declarative management of multiple localhost services through Tailscale Serve, with optional (explicitly gated) Funnel support.

### Prerequisites

- Linux host with Bash
- Tailscale CLI installed and authenticated (`tailscale up`)
- `ss` recommended for local port validation (from `iproute2`)

### Why Serve vs Funnel

- **Serve** exposes services privately to your **tailnet** only.
- **Funnel** exposes services to the **public internet**.
- This tool does **not** enable public exposure silently. Funnel entries require `--allow-funnel` and explicit confirmation (`--yes` or interactive prompt).

### Config model

Default config path:

- `/etc/tailscale-services/services.conf`

Override with `-c /path/to/file`.

Format (whitespace-separated, one service per line):

```text
<name> <localhost_target> <path_or_hostname> [exposure] [tls] [auth]
```

Fields:

- `name`: lowercase letters/digits/hyphen, unique
- `localhost_target`: localhost-only (`127.0.0.1:PORT`, `localhost:PORT`, `[::1]:PORT`, or just `PORT`)
- `path_or_hostname`: either path (`/`, `/api`, `/grafana`) or hostname (`app.example.ts.net`)
- `exposure` (optional): `tailnet` (default) or `funnel`
- `tls` (optional): `https` (default, listener 443) or `http` (listener 80)
- `auth` (optional): `tailnet` (default) or `none` (operator metadata)

Example:

```text
web      127.0.0.1:8080 /            tailnet https tailnet
api      localhost:9090  /api         tailnet https tailnet
publicui 127.0.0.1:7000 /public       funnel  https none
```

### Usage

```bash
./tailscale-services validate -c ./services.conf
./tailscale-services apply -c ./services.conf --dry-run
./tailscale-services apply -c ./services.conf
./tailscale-services status -c ./services.conf
./tailscale-services reset -c ./services.conf
```

Public exposure (Funnel) requires explicit flags:

```bash
./tailscale-services apply -c ./services.conf --allow-funnel --yes
```

### Routing behavior and hostname/path expectations

- Path routes are deterministic and checked for overlap conflicts.
- Multiple services can be served from one host, typically as:
  - `https://<node-name>.<tailnet-domain>/`
  - `https://<node-name>.<tailnet-domain>/api`
- The common request pattern `https://vps.<tailnet-domain>/<service>` is supported by path routes.
- Wildcard subdomain fan-out (for example, automatically mapping `*.vps.<tailnet-domain>`) is **not assumed**.
- If hostname-based routing is configured, this tool validates whether the local `tailscale serve` CLI advertises hostname support and fails with guidance if unsupported.

### Safe defaults and validation

- Rejects non-localhost backend targets.
- Validates service names, route syntax, duplicate/overlapping routes, missing binaries, and Tailscale auth state.
- Checks that backend target ports are listening (unless `TS_SKIP_PORT_CHECK=1` is set).
- `--dry-run` prints exact commands without changing system state.

### Troubleshooting

- `ERROR: Tailscale is not running/authenticated`  
  Run: `tailscale up`
- `target port not listening`  
  Start the local service or correct the target port.
- `hostname route ... requires ... --hostname support`  
  Upgrade Tailscale CLI or use path routes (for example `/service`).
- Funnel flag errors  
  Add `--allow-funnel` and confirmation (`--yes` or interactive prompt).

### Security considerations

- Keep sensitive/internal services on `tailnet` exposure.
- Use Funnel only when internet access is required.
- Apply tailnet ACL policy to restrict who can reach private Serve endpoints.
- No auth keys/secrets are logged by this tooling.

## `vault-mgmt`

ON/OFF toggle for the agent-vault management UI's network exposure over Tailscale.

- `vault-mgmt on [--persist]` — enable tailnet-reachable serve/funnel; auto-OFF after 30m unless `--persist`
- `vault-mgmt off` — localhost / SSH-tunnel only (default posture)
- `vault-mgmt status` — read-only state dump (serve, funnel, ports, nftables)
- `vault-mgmt verify` — assert the current mode's security properties

See `vault-mgmt` for the full implementation.