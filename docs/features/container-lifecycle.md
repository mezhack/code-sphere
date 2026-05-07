# Feature: Container Lifecycle

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

Student containers are not always running. They're started when needed and stopped when idle, freeing resources for other students. This feature manages that full lifecycle: spawning a fresh container with a unique authentication token, polling its health, and shutting it down after inactivity.

The lifecycle must be invisible to the student. From their perspective, they log in and the workspace appears. They use it, walk away, come back later, and the workspace is back. The mechanics of container start, stop, and restart should never surface as errors.

## Behavior

### Spawn a Container (on login)

1. Student logs in successfully and reaches `/conectar`.
2. Portal checks if container `sala_alunoXX` is in `running` state.
   - If yes and there's a valid session token, reuse it. Skip to step 9.
3. Portal generates a fresh 32-character random token (alphanumeric).
4. Portal reads the existing container's configuration (image, hostname, env vars, volumes, network, labels, resource limits) via Docker API.
5. Portal removes any existing `PASSWORD` from the env list, appends `PASSWORD=<new-token>`.
6. Portal removes the container.
7. Portal creates a new container with the same configuration but the new env vars, attached to the same network.
8. Portal starts the new container.
9. Portal **polls** the container's HTTP port (port 8443 by default for code-server) until it responds with status 200 or 302.
10. If polling succeeds, portal updates the session with the new token.
11. Portal renders `/conectar` page with auto-submit form to `/code/alunoXX/login` containing the token.
12. Browser submits the form, code-server authenticates, student lands in workspace.

### Idle Cleanup (Garbage Collector)

A background thread (`gc_loop`) runs every 60 seconds:

1. Reads `sessoes.json`.
2. For each session, computes `now - ultimo_acesso` in seconds.
3. If the time exceeds `INATIVIDADE_MINUTOS * 60`, the session is expired.
4. For each expired session: stop the corresponding container, remove the session entry.
5. Writes back `sessoes.json` if any sessions were removed.

### Heartbeat (keep alive)

While the student is using their workspace, JavaScript in the browser hits the portal periodically:

- `/heartbeat` (POST, every 60s): updates `ultimo_acesso` for the active session.
- `/ping` (GET, every 30s): same update, but also checks if the container is still running. If the container was stopped (e.g., admin stopped it, or GC stopped it during a long pause), `/ping` returns `{ok: false, redirect: "/conectar"}`.

### Inputs

- **Spawn:** student username, fresh token
- **GC:** current time, `sessoes.json`, `INATIVIDADE_MINUTOS` config
- **Heartbeat:** session cookie

### Outputs

- **Spawn:** running container with student-specific token; updated session
- **GC:** stopped containers; cleaned-up sessions
- **Heartbeat:** updated `ultimo_acesso` timestamp

### Edge Cases

- **Container does not exist (`docker.errors.NotFound`).** The container was never created (setup incomplete) or was manually removed. Portal returns false from `iniciar_container`, student sees "Erro ao iniciar seu ambiente. Avise o professor."
- **Container in `running` state but code-server not yet responding.** Portal waits up to 15 seconds (already-running case) for HTTP to respond. If no response, returns false.
- **Container starts but never becomes healthy (45s timeout).** Portal logs a warning and returns false. Student sees the same generic error.
- **Multiple simultaneous starts of the same container.** Docker API serializes container operations. The second `remove()` would fail; the function catches all exceptions and returns false.
- **Student closes browser without logging out.** GC will stop the container after `INATIVIDADE_MINUTOS`. Session remains in `sessoes.json` until expiry.
- **GC thread crashes.** Logged via `app.logger.exception`. The thread loop's outer try/except keeps the loop running. If the entire thread dies, containers leak (won't be stopped) until portal restart.

### Failure Modes

- **Docker socket unreachable.** `docker.from_env()` raises. The portal logs the error and the user sees "Erro ao iniciar seu ambiente."
- **Disk full.** Container start may fail with various errors. Generic error to user.
- **Network creation failure.** `sala_net` is created by the compose stack. If missing, container start fails. Setup script ensures it exists.

## Integration Points

- **Authentication:** must succeed before lifecycle activates.
- **Admin Panel:** admin can manually stop or restart any container, bypassing the lifecycle.
- **Auto-Reconnect:** depends on `/ping` to detect that the container was stopped by GC.

## Implementation References

- `portal/app.py:iniciar_container` — spawn logic
- `portal/app.py:aguardar_code_server` — health-check polling
- `portal/app.py:parar_container` — stop logic
- `portal/app.py:gc_loop` — idle cleanup loop
- `portal/app.py:ping`, `portal/app.py:heartbeat` — keep-alive endpoints
- `preaquecer.sh` — pre-warm script that starts containers ahead of class

## Related

- [ADR-0005: On-demand container spawning](../decisions/0005-on-demand-containers.md)
- [Feature: Authentication](./authentication.md)
- [Feature: Auto-Reconnect](./auto-reconnect.md)
