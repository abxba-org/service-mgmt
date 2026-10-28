# service-mgmt

Service management configuration and helper scripts for the agent-vault tailnet broadcast.

## vault-mgmt

ON/OFF toggle for the agent-vault management UI's network exposure over Tailscale.

- `vault-mgmt on [--persist]` — enable tailnet-reachable serve/funnel; auto-OFF after 30m unless `--persist`
- `vault-mgmt off` — localhost / SSH-tunnel only (default posture)
- `vault-mgmt status` — read-only state dump (serve, funnel, ports, nftables)
- `vault-mgmt verify` — assert the current mode's security properties

See `vault-mgmt` for the full implementation.