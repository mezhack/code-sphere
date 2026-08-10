# Architecture Decision Records (ADRs)

This directory contains the architectural decisions made for this project. Each ADR documents one decision: what we chose, what alternatives we considered, and why we chose what we did.

## Why ADRs Matter

Code shows you *what* the system does. Comments explain *how*. ADRs explain *why*.

Future maintainers (including AI agents) need to know which constraints drove decisions. Without ADRs, well-meaning changes can silently undo important trade-offs. With ADRs, anyone proposing a change can see what they would be giving up.

## Format

Each ADR follows this template:

```markdown
# ADR-NNNN: Title

**Status:** Accepted | Superseded by ADR-XXXX | Deprecated
**Date:** YYYY-MM-DD
**Decision Makers:** (names or roles)

## Context

What problem are we solving? What constraints exist? What is the current state?

## Decision

What did we decide to do? Be specific.

## Alternatives Considered

What other options did we evaluate? Why did we reject them?

## Consequences

What does this decision enable? What does it prevent? What new problems does it create?

## References

Links to related discussions, ADRs, or external resources.
```

## Index

| # | Title | Status |
|---|-------|--------|
| [0001](./0001-single-server-architecture.md) | Single-server architecture (no clustering) | Accepted |
| [0002](./0002-traefik-reverse-proxy.md) | Traefik for reverse proxy and routing | Accepted |
| [0003](./0003-flask-portal.md) | Flask + Gunicorn for the portal | Accepted |
| [0004](./0004-cloudflare-tunnel.md) | Cloudflare Tunnel for HTTPS | Accepted |
| [0005](./0005-on-demand-containers.md) | On-demand container spawning | Accepted |
| [0006](./0006-argon2-passwords.md) | Argon2 for password hashing | Accepted |
| [0007](./0007-puid-pgid-911.md) | PUID/PGID 911:1001 for student volumes | Accepted |
| [0008](./0008-version-check-github.md) | GitHub Releases API for update checking | Accepted |
| [0009](./0009-fast-restart-s6.md) | Fast restart via s6-svc for pre-warmed containers | Accepted |
| [0010](./0010-pygame-zero-sem-window-manager.md) | Pygame Zero on the virtual display without a window manager | Accepted |
| [0011](./0011-audio-pcm-cru-via-websockify.md) | Audio to the browser as raw PCM over websockify | Accepted |

## Adding a New ADR

1. Pick the next available number (e.g., `0009`).
2. Create `NNNN-short-kebab-case-title.md` using the template above.
3. Add the entry to the index in this file.
4. Reference the ADR from any feature spec or code comment that depends on the decision.

## Status Lifecycle

- **Proposed** — under discussion, not yet implemented
- **Accepted** — decided and implemented
- **Superseded** — replaced by a newer ADR (link to it)
- **Deprecated** — no longer relevant but kept for historical context
