# ADR-0004: Cloudflare Tunnel for HTTPS

**Status:** Accepted
**Date:** 2026-04-27
**Decision Makers:** Project lead

## Context

Managed Chromebooks in school environments enforce HSTS-like policies that block plain HTTP access to web applications. Students literally cannot reach `http://192.168.1.41/` even with the typical "Advanced → Proceed anyway" workaround — the proceed button does not appear under managed policy.

The system must be reachable over HTTPS. The school environment has these constraints:

- **No public domain.** The school doesn't own a domain or wants to use one.
- **No router access.** The teacher cannot configure port forwarding.
- **No Google Admin Console access.** Cannot install custom certificates on Chromebooks.
- **Local-only network.** Server is on `192.168.x.x`, not reachable from the public internet.

This combination rules out Let's Encrypt (needs a public domain), self-signed certificates (Chromebooks block them), and custom CA installation (no Admin Console).

## Decision

Use **Cloudflare Tunnel (cloudflared)** to provide HTTPS. The tunnel works by establishing an outbound connection from the server to Cloudflare's edge, exposing the local Traefik through a Cloudflare-issued URL with a valid certificate.

Two operating modes are supported:

1. **Anonymous mode** (default): generates a `*.trycloudflare.com` URL that changes on each restart. No account required.
2. **Authenticated mode**: requires a free Cloudflare account and a tunnel token. URL is fixed (e.g., `sala.example.com.cloudflareaccess.com`).

The cloudflared container runs as a sibling to the portal and Traefik in the same `docker-compose.yml`.

## Alternatives Considered

### Let's Encrypt with DuckDNS

Pros: free, fully self-hosted, certificate is properly trusted.

Rejected because: requires port forwarding on the school router (which the teacher doesn't have access to) AND a public IP that is reachable from Let's Encrypt's validation servers.

### Self-signed certificate with custom CA

Pros: works on a fully isolated network.

Rejected because: requires installing the custom CA on every Chromebook, which requires Google Admin Console access (which the teacher doesn't have). Also, managed Chromebooks may block custom CAs even when installed.

### Tailscale Funnel

Pros: similar concept to Cloudflare Tunnel, integrates well with existing Tailscale users.

Rejected because: requires Tailscale on every client device (Chromebook installation is awkward at best), and the school can't dictate what runs on managed devices.

### ngrok

Pros: similar to Cloudflare Tunnel.

Rejected because: free tier has hard rate limits and changing URLs that are even more annoying than Cloudflare's anonymous mode. Paid tier defeats the "free for teachers" goal.

## Consequences

### Enabled

- HTTPS access works on managed Chromebooks without any device-side changes.
- No router configuration needed — outbound HTTPS from the server is enough.
- No public domain needed.
- Free for the teacher.

### Prevented

- The system depends on Cloudflare's availability. If Cloudflare is down, the tunnel is down. (Local IP fallback still works for non-managed devices.)
- The system depends on outbound internet from the server. Air-gapped deployments need a different solution.
- In anonymous mode, the URL changes on restart. Teachers must re-share the URL each session unless they use authenticated mode.

### New problems introduced

- The teacher needs to understand the difference between anonymous and authenticated modes.
- Changing the cloudflared image version may require token reformatting if Cloudflare changes its API.
- The `./url_atual.sh` script depends on parsing log output, which is fragile if cloudflared changes its log format.

## References

- [Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- `gerar.sh` — where the cloudflared service is templated into the docker-compose.yml
- `url_atual.sh` — script to extract the anonymous tunnel URL from logs
