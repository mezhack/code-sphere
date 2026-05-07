# ADR-0002: Traefik for Reverse Proxy and Routing

**Status:** Accepted
**Date:** 2026-04-25
**Decision Makers:** Project lead

## Context

The system has one public entry point (port 80) but routes traffic to many internal services: the Flask portal, and one code-server container per logged-in student. Routes look like `/admin` for the portal and `/code/aluno01/`, `/code/aluno02/`, etc. for student environments.

Student containers are spawned on demand by the portal. The reverse proxy must discover them automatically — restarting the proxy every time a student logs in is not acceptable.

The proxy must also handle WebSocket connections (code-server uses WebSockets heavily for real-time UI updates and terminal sessions).

## Decision

Use **Traefik v3.6** as the reverse proxy. Each container declares its own routing rules through Docker labels. Traefik watches the Docker socket and updates its routing table automatically when containers start or stop.

Example routing labels for the portal container:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.portal.rule=PathPrefix(`/`)"
  - "traefik.http.services.portal.loadbalancer.server.port=5000"
```

## Alternatives Considered

### nginx with templated config

Pros: extremely well-known, vast documentation, mature.

Rejected because: dynamic routing (containers appearing and disappearing) requires either reload-on-change (which drops connections) or a sidecar like `nginx-proxy`. The label-based approach in Traefik is fundamentally cleaner for this use case.

### Caddy

Pros: similar capabilities to Traefik, simpler config syntax, automatic HTTPS support.

Rejected because: Docker label support is less mature than Traefik's, and the project doesn't need Caddy's automatic HTTPS (we use Cloudflare Tunnel instead, see ADR-0004).

### HAProxy

Pros: extremely fast, battle-tested at scale.

Rejected because: dynamic configuration story is weaker than Traefik's, and we don't need its performance ceiling.

### No reverse proxy (port-per-student)

Pros: simplest possible architecture.

Rejected because: would require students to remember per-student port numbers (e.g., `192.168.1.41:8001` for student 01). Many school networks block non-standard ports. URL paths are universally accessible.

## Consequences

### Enabled

- Student containers can spawn dynamically without proxy restart.
- Single port (80 or 443) is enough for the entire deployment.
- Routing rules live next to the containers they describe (in `docker-compose.yml`), not in a separate config file.

### Prevented

- Cannot easily run two independent classroom installations on the same Docker engine without label conflicts.
- Customizing low-level proxy behavior (custom rate limiting, complex rewrites) requires learning Traefik's specific syntax.

### Known issues

- **Traefik 3.2 is incompatible with Docker API 1.40+**. Versions 3.2 and earlier fail with "client version 1.24 is too old". The project pins to v3.6 specifically because of this. Any version bump must verify Docker API compatibility.

## References

- [Traefik documentation](https://doc.traefik.io/traefik/)
- [Architecture overview](../architecture.md)
