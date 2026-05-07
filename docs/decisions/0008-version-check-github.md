# ADR-0008: GitHub Releases API for Update Checking

**Status:** Accepted
**Date:** 2026-04-29
**Decision Makers:** Project lead

## Context

Teachers may run an old version of the platform without realizing newer versions are available. They might request features that are already implemented in newer releases, or miss bug fixes that would help them. The system should let the teacher know when a newer version exists.

The check must:
- Not break the admin panel if the server has no internet.
- Not require a Cloudflare/AWS/etc. account or any infrastructure beyond what already exists.
- Not collect telemetry or send any data about the school's installation.
- Not annoy the teacher — a newer version is informational, not blocking.

## Decision

The portal queries the **GitHub Releases REST API** (`https://api.github.com/repos/<owner>/<repo>/releases/latest`) to fetch the latest release tag, and compares it to the version stored in `portal/version.json`.

The check happens:
- When the admin panel is loaded (cached for 1 hour).
- When the admin clicks the version button (forces a refresh).

If the request fails (no internet, API down, repo not found), the admin panel renders normally without the version banner. No error is shown to the teacher unless they explicitly clicked to check.

Comparison uses tuple comparison of parsed semver components: `(1, 2, 0) > (1, 0, 0)`.

## Alternatives Considered

### Custom version server

Pros: full control, can include richer metadata (release notes, deprecation warnings).

Rejected because: requires hosting and maintaining infrastructure, which violates the project's "no extra services" constraint.

### Update through Docker Hub tags

Pros: aligns with how Docker images are versioned anyway.

Rejected because: the project distributes via GitHub (source) primarily, not Docker Hub. Docker Hub auth and rate limits add complexity without benefit.

### No update check at all

Pros: simplest possible.

Rejected because: the documented use case (teacher requesting features that already exist) is real and easy to prevent.

### Check on every page load (no cache)

Pros: always shows the latest information.

Rejected because: GitHub's unauthenticated rate limit is 60 requests per hour per IP. A busy admin panel could exceed this. The 1-hour cache stays well under the limit.

## Consequences

### Enabled

- Teachers see when their installation is outdated without any setup.
- The check is informational only — never blocks operation.
- Works without authentication (uses the public GitHub API).

### Prevented

- Cannot check for updates if the GitHub repository is private or moved.
- Cannot push notifications about urgent security updates — teachers see them only when they happen to load the admin panel.

### New problems introduced

- **GitHub repo path is hardcoded.** If the project moves, every existing installation needs to be told the new path. Could be mitigated with an environment variable in the future.
- **Rate limit risk.** With 1-hour cache and many installations on shared corporate IPs, there's a theoretical risk of cache misses synchronizing and exceeding 60/hour. Unlikely in practice given the small user base.

## References

- `portal/app.py:verificar_atualizacao` — the implementation
- `portal/version.json` — the local version file
- [GitHub REST API: releases](https://docs.github.com/en/rest/releases/releases)
- [Semantic Versioning](https://semver.org/)
