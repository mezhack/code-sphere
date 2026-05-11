# Feature: Version Check

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-05-11

## Context

Teachers may run an outdated version of the platform without realizing it. They might request features already implemented, or miss bug fixes that would help them. This feature shows the current version in the admin panel and displays a banner when a newer version is available on GitHub.

Students can also follow platform changes through a public changelog page linked from the login screen.

See [ADR-0008](../decisions/0008-version-check-github.md) for the decision rationale.

## Behavior

### Version Badge on Login Page

The student login page shows the current version as a clickable badge at the bottom of the card:

```
Versão 1.0.2 — Changelog · Sobre
```

- "Versão 1.0.2" is injected via a Flask context processor (`injetar_versao`) that reads `version.json` and exposes `versao_atual` to all templates.
- "Changelog" links to `/changelog` (public, no auth required).
- "Sobre" links to `/about` (public, no auth required).

### Public Changelog Page (`/changelog`)

- Accessible to anyone, including students who are not logged in.
- Reads `version.json` and renders all version entries in reverse order.
- "← Voltar" button returns to `/`.

### Display Current Version (Admin Panel)

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
- HTML changelog pages (admin and public).
- Version badge injected into every template via context processor.

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
- **Login Page:** public version badge with links to `/changelog` and `/about`.

## Implementation References

- `portal/app.py:versao_local` — reads `version.json`
- `portal/app.py:verificar_atualizacao` — queries GitHub and caches
- `portal/app.py:admin_api_versao` — JSON endpoint consumed by JS
- `portal/app.py:admin_changelog` — admin changelog page route
- `portal/app.py:changelog_publico` — public `/changelog` route (no auth)
- `portal/app.py:about` — public `/about` route (no auth)
- `portal/app.py:injetar_versao` — context processor that exposes `versao_atual` to all templates
- `portal/templates/login.html` — version badge and links at bottom of card
- `portal/templates/changelog.html` — public changelog UI
- `portal/templates/about.html` — credits page
- `portal/templates/admin_painel.html` — JavaScript that renders the update banner
- `portal/templates/admin_changelog.html` — admin changelog UI
- `portal/version.json` — version metadata

## Related

- [ADR-0008: GitHub Releases API for update checking](../decisions/0008-version-check-github.md)
- [Feature: Admin Panel](./admin-panel.md)
