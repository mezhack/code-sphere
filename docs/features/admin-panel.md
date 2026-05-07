# Feature: Admin Panel

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

The teacher needs to monitor the classroom in real time and intervene when something goes wrong: reset a forgotten password, restart a stuck container, see who's actually working versus who's left their browser open. The admin panel provides a single dashboard for these operations without requiring SSH access to the server.

The panel is consulted live during class. It must load fast (under 1 second), update without full-page reloads, and not lock up if some containers are misbehaving.

## Behavior

### Initial Load

1. Admin visits `/admin/painel` (after login).
2. Portal calls `listar_containers_ativos()` — a single Docker API call with a filter that returns all running containers matching `name: sala_aluno*`.
3. For each student in `alunos.json`, portal builds a row:
   - Username
   - Whether they need to change password (`precisa_trocar`)
   - Last login timestamp (from `alunos.json`)
   - Whether the container is currently running (from the set above)
   - Idle time in minutes (from `sessoes.json`)
4. Portal also reads `/proc/meminfo` to show server-level RAM total and free.
5. Page renders with all rows. CPU and RAM per student are shown as "—" initially.

### Live Stats Refresh (every 30s)

JavaScript on the panel calls `/admin/api/stats`:

1. Portal again gets the active set in one call.
2. For each running container, portal calls `stats_container()` to get CPU% and RAM MB.
3. `stats_container` uses a 3-second timeout per container (in a worker thread) so a hung container can't block the entire response.
4. Returns JSON with all stats.
5. JavaScript updates each row in place — no full page reload.

### Actions

The admin can perform per-student actions:

- **🔑 Reset password** — `POST /admin/resetar/<aluno>`. Hash reset to initial password, `precisa_trocar` set to true.
- **↺ Restart container** — `POST /admin/reiniciar/<aluno>`. Stops the container, generates a new token, starts a fresh one.
- **⏹ Stop container** — `POST /admin/parar/<aluno>`. Stops the container; session is removed.
- **📁 View files** — `GET /admin/arquivos/<aluno>`. Opens the file browser (separate feature).

Bulk actions:

- **⏹ Stop all** — `POST /admin/parar-todos`. Iterates and stops all running student containers.
- **🔑 Reset all passwords** — `POST /admin/resetar-todas` with confirmation text "RESETAR TODAS". Resets every student to the initial password.

### Inputs

- Admin's session cookie (must have `admin = True`).
- POST forms for actions.

### Outputs

- HTML page with student rows.
- JSON from `/admin/api/stats` for live updates.
- Side effects: stopped/started containers, modified `alunos.json` and `sessoes.json`.
- Flash messages on success or failure.

### Edge Cases

- **Many containers running, some unresponsive.** The 3-second timeout per `stats_container` prevents a hung container from blocking the API response. Other students' stats still appear; the unresponsive one shows "—".
- **Action fired while admin's session expired.** `checar_admin()` returns 403. Admin sees a generic error and must re-login.
- **Container removed externally (`docker rm`).** `parar_container` catches `NotFound` silently. `stats_container` returns empty dict.
- **`alunos.json` is locked while admin clicks reset.** The lock is held briefly (write only), so this is unlikely. If it happens, the request waits for the lock.

### Failure Modes

- **Docker socket unreachable.** Stats API returns mostly empty data. Container actions fail with the generic "Falha ao..." flash message.
- **`/proc/meminfo` not readable.** Server RAM stats show as `null`; the rest of the panel works.

## Pedagogical Notes

The admin panel is intentionally read-write but **not a teaching tool**. It does not show student code (the file viewer does that, in a separate route), grade work, or send messages. Its scope is operational: keep the classroom running.

This separation prevents the admin panel from becoming a complex LMS-lite. Teachers who want grading can use Google Classroom or similar; the platform doesn't compete with that.

## Integration Points

- **Authentication:** admin login required for all routes.
- **Container Lifecycle:** restart and stop actions go through the same code as auto-spawn.
- **File Viewer:** the "📁 Arquivos" link opens the file viewer for a specific student.
- **Version Check:** the version banner is rendered at the top of the panel.

## Implementation References

- `portal/app.py:admin_painel` — main panel view
- `portal/app.py:admin_api_stats` — live stats endpoint
- `portal/app.py:admin_resetar_senha`, `admin_parar_container`, `admin_reiniciar_container` — per-student actions
- `portal/app.py:admin_parar_todos`, `admin_resetar_todas` — bulk actions
- `portal/app.py:listar_containers_ativos` — single-call Docker query
- `portal/templates/admin_painel.html` — UI and JavaScript

## Related

- [Feature: Authentication](./authentication.md)
- [Feature: Container Lifecycle](./container-lifecycle.md)
- [Feature: File Viewer](./file-viewer.md)
- [Feature: Version Check](./version-check.md)
