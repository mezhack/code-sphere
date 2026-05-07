# Feature: Cloudflare HTTPS

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

Managed Chromebooks block plain HTTP. The school environment makes traditional HTTPS solutions unworkable (no domain, no router access, no admin console). Cloudflare Tunnel solves this by establishing an outbound connection from the server to Cloudflare's edge, which then exposes the platform via a Cloudflare-issued URL with a valid TLS certificate.

See [ADR-0004](../decisions/0004-cloudflare-tunnel.md) for the decision rationale and alternatives.

## Behavior

### Anonymous Mode (no Cloudflare account)

1. Setup script asks if HTTPS via Cloudflare Tunnel should be enabled.
2. User answers yes, picks "basic mode" (option 1).
3. `config.env` is written with `CLOUDFLARE_TUNNEL=true` and empty `CLOUDFLARE_TOKEN`.
4. `gerar.sh` includes a `cloudflared` service in `docker-compose.yml` running `tunnel --no-autoupdate --url http://traefik:80`.
5. On startup, cloudflared connects to Cloudflare and prints a generated URL like `https://abc-def-123.trycloudflare.com` to its logs.
6. The teacher runs `./url_atual.sh` (or `./url_atual.sh --watch`) to extract the URL from the logs and display it.
7. Students access the platform via the displayed URL.

### Authenticated Mode (fixed URL)

1. Teacher creates a free Cloudflare account.
2. Teacher creates a tunnel in the Zero Trust dashboard, configures hostname routing.
3. Teacher copies the tunnel token.
4. Setup asks for the token; teacher pastes it.
5. `config.env` is written with `CLOUDFLARE_TUNNEL=true` and the token.
6. `gerar.sh` includes a `cloudflared` service running `tunnel --no-autoupdate run` with `TUNNEL_TOKEN` env var.
7. The tunnel uses the fixed URL configured in the Cloudflare dashboard.
8. The URL never changes across restarts.

### Inputs

- `CLOUDFLARE_TUNNEL` (boolean string in `config.env`).
- `CLOUDFLARE_TOKEN` (string in `config.env`, optional).

### Outputs

- `cloudflared` service in `docker-compose.yml`.
- Outbound HTTPS connection from server to Cloudflare.
- A working public URL with valid TLS certificate.

### Edge Cases

- **No outbound internet from server.** The tunnel fails to establish. Cloudflared logs show connection errors. The local IP fallback (`http://192.168.x.x/`) still works for unmanaged devices.
- **Cloudflare's edge briefly unavailable.** Cloudflared reconnects automatically. Brief outage but no manual intervention needed.
- **Token expired (authenticated mode).** Tunnel fails to connect. Teacher must re-create the token in the Cloudflare dashboard and update `config.env`.
- **`url_atual.sh` runs before tunnel finishes connecting.** Returns "URL ainda não disponível." Teacher uses `--watch` or retries.
- **Multiple tunnels using the same token.** Cloudflare allows this; both forward the same hostname. Useful for failover but not used in our setup.

### Failure Modes

- **Cloudflared image not pullable.** Docker can't pull `cloudflare/cloudflared:latest`. The whole compose stack fails. Network issue or registry blocked.
- **Token format changed by Cloudflare.** If Cloudflare changes their API, existing tokens may stop working. Documented as a known risk in the ADR.

## Pedagogical Notes

The Cloudflare Tunnel does not affect the experience of using the platform. It only affects how the URL looks and how it's reached. From the student's perspective, they type a URL and they're at the login page.

Teachers should bookmark the URL on their projector computer to display at the start of class. In anonymous mode, this URL changes after every server restart, so the teacher must update the bookmark or re-display via `./url_atual.sh`.

## Integration Points

- **Setup:** `setup.sh` configures the feature interactively.
- **Generation:** `gerar.sh` includes the cloudflared service when `CLOUDFLARE_TUNNEL=true`.
- **Operation:** `iniciar.sh` adds `cloudflared` to the services that get started; `parar.sh` stops it along with the rest.

## Implementation References

- `setup.sh` — interactive prompts for Cloudflare configuration
- `gerar.sh` — generates the cloudflared service in docker-compose.yml
- `url_atual.sh` — extracts the URL from cloudflared logs (anonymous mode only)

## Related

- [ADR-0004: Cloudflare Tunnel for HTTPS](../decisions/0004-cloudflare-tunnel.md)
- [Operations: Installation](../operations/installation.md)
