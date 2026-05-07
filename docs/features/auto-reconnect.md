# Feature: Auto-Reconnect

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

The garbage collector stops idle containers to save resources. But "idle" is a heuristic — a student may take a 35-minute break, return to their browser, and find their workspace mysteriously broken. Without intervention, they would see a `502 Bad Gateway` from Traefik (because the upstream container is gone) or a code-server "Welcome" screen requesting a password they don't know.

This feature ensures that whenever a container is stopped while the student's tab is open, the browser automatically detects this and seamlessly recovers.

## Behavior

### Active Session Detection

While the student is logged in and viewing the workspace, JavaScript in the auto-reconnect page (rendered after login) runs two timers:

1. **Heartbeat (60s):** `POST /heartbeat` — refreshes `ultimo_acesso` so the GC won't stop the container.
2. **Ping (30s):** `GET /ping` — checks if the container is still running.

### Recovery Flow

When the GC has stopped the container or the session has expired:

1. The next `/ping` call returns one of:
   - `{ok: false, login: true}` — the session is invalid; redirect to `/login`.
   - `{ok: false, redirect: "/conectar"}` — the session is valid but the container is stopped; redirect to `/conectar`.
2. JavaScript performs `window.location.href = redirect_url`.
3. If redirected to `/conectar`, the portal sees a valid session and starts the container fresh (same flow as initial login).
4. The student sees the loading screen briefly, then auto-submits to the workspace.

### Inputs

- Browser timer events (every 30s for ping, every 60s for heartbeat).
- Session cookie containing student's username.

### Outputs

- Updated `ultimo_acesso` in `sessoes.json` (heartbeat).
- JSON response from `/ping` indicating action to take.
- Browser redirect to either `/login` or `/conectar` if needed.

### Edge Cases

- **Network blip during ping.** Catch block silently ignores network errors. The next ping (30s later) will succeed if the network recovered.
- **Student closes the tab during reconnect.** No harm — they'll re-login next time, getting a fresh container.
- **Container is starting (not yet running) when ping arrives.** `container_rodando()` returns false during boot, so ping says "redirect to /conectar". /conectar sees the container starting and waits for the health check.
- **Page is in background tab.** Browsers throttle JavaScript timers in inactive tabs but still fire them eventually. Recovery may take longer but still happens.

### Failure Modes

- **Portal is down.** Pings fail. Student sees stale UI; on reload they get the portal error page or a Traefik error.
- **Container can't be restarted (e.g., image deleted).** `/conectar` returns the error page with "Avise o professor."
- **Token mismatch after restart.** Each restart generates a fresh token, embedded in the new auto-submit form. The browser submits this fresh token, so no mismatch occurs in normal operation.

## Why This Matters Pedagogically

Without this feature, every student break longer than the timeout becomes a support call to the teacher: "professor, meu VS Code parou." This drains attention from teaching. With auto-reconnect, the student goes to lunch, comes back, sees a brief loading screen, and continues working. The system disappears.

## Integration Points

- **Container Lifecycle:** auto-reconnect triggers `iniciar_container` via `/conectar` redirect.
- **Authentication:** if session expired, redirects through full login flow.

## Implementation References

- `portal/app.py:ping` — endpoint that returns redirect instructions
- `portal/app.py:heartbeat` — endpoint that keeps the session alive
- `portal/templates/conectar.html` — JavaScript timers for ping and heartbeat

## Related

- [Feature: Container Lifecycle](./container-lifecycle.md)
- [ADR-0005: On-demand container spawning](../decisions/0005-on-demand-containers.md)
