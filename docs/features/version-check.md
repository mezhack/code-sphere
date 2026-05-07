# Feature: Version Check

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

Teachers may run an outdated version of the platform without realizing it. They might request features already implemented, or miss bug fixes that would help them. This feature shows the current version in the admin panel and displays a banner when a newer version is available on GitHub.

See [ADR-0008](../decisions/0008-version-check-github.md) for the decision rationale.

## Behavior

### Display Current Version

1. Admin panel header shows a button labeled `📋 v1.0.0` (or whatever the current version is).
2. Clicking the button opens `/admin/changelog` showing the full changelog from `version.json`.

### Check for Updates

1. When the admin panel loads, JavaScript calls `/admin/api/versao`.
2. Portal reads the local version from `portal/version.json`.
3. Portal calls `https://api.github.com/repos/<owner>/<repo>/releases/latest` with a 5-second timeout.
4. Portal parses the response, extracts the `tag_name` (e.g., `v1.1.0`), strips the leading `v`.
5. Portal compares versions using tuple comparison: `(1,1,0) > (1,0,0)`.
6. Returns JSON with: `versao_local`, `versao_remota`, `tem_atualizacao`, `url_release`, `erro`.
7. Result is cached for 1 hour to avoid hitting GitHub's rate limit.

### Display Update Banner

JavaScript receives the JSON and:
- If `tem_atualizacao` is true: shows a yellow banner with "🆕 Nova versão: vX.Y.Z" and a "Ver novidades" button linking to the GitHub release.
- If `tem_atualizacao` is false but `versao_remota` is set: shows a green confirmation "✔ Sistema atualizado" that auto-hides after 5 seconds.
- If `erro` is set: silently shows nothing (no internet, no banner, panel works normally).

### Inputs

- `portal/version.json` — local version file (read on each request, no caching).
- HTTP request to GitHub Releases API.

### Outputs

- JSON with version comparison.
- HTML banner in admin panel.
- HTML changelog page.

### Edge Cases

- **No internet on server.** `urllib.error.URLError` is caught, returns `erro: "sem_internet"`. JavaScript shows nothing. Panel works.
- **GitHub API rate limit hit (60/hour unauthenticated).** Returns 403 from GitHub. Cached result stays until 1-hour expiry.
- **GitHub repo doesn't exist or moved.** Returns 404. `versao_remota` is null. Banner not shown.
- **Local `version.json` missing or invalid.** Falls back to "desconhecida" version. Comparison fails (since "desconhecida" doesn't parse to integers); banner not shown.
- **Tag format unexpected** (e.g., `release-1.0.0` instead of `v1.0.0`). The strip(`v`) would leave `release-1.0.0`, which fails to parse. Banner not shown.

### Failure Modes

- **GitHub API outage.** Cache returns last known result if within 1 hour, otherwise no banner.
- **Slow network.** 5-second timeout means worst-case 5-second delay before panel finishes loading. JavaScript runs the version check async, so the panel renders first.

## Cache Behavior

- The cache is in-memory in the portal process.
- Cleared on portal restart.
- Refreshed when `force=1` query param is passed (currently not exposed in UI).
- Lifetime: 3600 seconds (1 hour).
- Single-instance only — no shared cache across portal replicas (acceptable since we have one replica per ADR-0001).

## Integration Points

- **Admin Panel:** the banner renders at the top of the panel; the version button is in the header.

## Implementation References

- `portal/app.py:versao_local` — reads `version.json`
- `portal/app.py:verificar_atualizacao` — queries GitHub and caches
- `portal/app.py:admin_api_versao` — JSON endpoint consumed by JS
- `portal/app.py:admin_changelog` — full changelog page route
- `portal/templates/admin_painel.html` — JavaScript that renders the banner
- `portal/templates/admin_changelog.html` — changelog UI
- `portal/version.json` — version metadata

## Related

- [ADR-0008: GitHub Releases API for update checking](../decisions/0008-version-check-github.md)
- [Feature: Admin Panel](./admin-panel.md)
