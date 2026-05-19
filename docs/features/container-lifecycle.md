# Feature: Container Lifecycle

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-05-19

## Context

Student containers are not always running. They're started when needed and stopped when idle, freeing resources for other students. This feature manages that full lifecycle: spawning a container with a unique authentication token, polling its health, and shutting it down after inactivity.

The lifecycle must be invisible to the student. From their perspective, they log in and the workspace appears. They use it, walk away, come back later, and the workspace is back. The mechanics of container start, stop, and restart should never surface as errors.

## Password Source Priority

**Critical finding (confirmed by testing):** The `PASSWORD` environment variable injected at container creation takes priority over `config.yaml` in the `linuxserver/code-server` image. The run script reads `$PASSWORD` via `with-contenv` from `/var/run/s6/container_environment/PASSWORD`; if that file is present and non-empty, code-server uses it regardless of any `config.yaml`. The `config.yaml` file is only authoritative when no `PASSWORD` env var is set.

This is the opposite of what the original documentation stated. The `_senha_config_yaml` helper function is retained for reading, but is no longer used to determine the effective password.

## Behavior

### Spawn a Container (on login)

#### Path A — container already running with the matching token

1. Student reaches `/conectar`.
2. Portal checks: container `sala_alunoXX` is `running`.
3. Portal reads the `PASSWORD` value from the container's config (original env at creation time).
4. If it matches the current session token: reuse the token, return `/conectar` with `aguardando=False`.
5. After 1.5 s the "Abrir VS Code" and "Abrir Monitor" buttons are enabled. Student clicks to open the workspace or virtual display in a new tab.

#### Path B — container already running but with a different token (pre-warmed)

This is the normal case after `./preaquecer.sh` has been run.

1. Student reaches `/conectar`.
2. Container is running, but `PASSWORD` in its config doesn't match the new session token.
3. Portal calls `_reiniciar_code_server(aluno, token)`:
   a. Via `docker exec`, overwrites `/var/run/s6/container_environment/PASSWORD` with the new token.
   b. Deletes `alunos/alunoXX/.config/code-server/config.yaml` if it exists (cleanup).
   c. Via `docker exec`, calls `s6-svc -r /run/service/svc-code-server` to restart only the code-server process.
   d. Both exec calls check exit code; any non-zero exit triggers fallback to Path C.
4. Portal returns `/conectar` with `aguardando=True` and returns the response immediately.
5. In background, `aguardar_code_server` polls until code-server responds (~1–2 seconds).
6. Client JS polls `/aguardar` every 2 s; on success, enables the "Abrir VS Code" and "Abrir Monitor" buttons.

#### Path C — container not running, or fast restart failed (fallback)

1. Student reaches `/conectar` (or Path B fallback triggered).
2. Portal generates a fresh 32-character random token.
3. Portal saves the token to `sessoes.json` immediately.
4. Portal renders `/conectar` with `aguardando=True` and **returns the response** — browser shows loading page.
5. In a background thread, `iniciar_container` runs:
   a. If the container was running (Path B fallback): stop it.
   b. Delete `alunos/alunoXX/.config/code-server/config.yaml` if it exists.
   c. Read the existing container's configuration (image, hostname, env vars, volumes, network, labels, resource limits) via Docker API.
   d. Remove `PASSWORD` from env list, append `PASSWORD=<new-token>`.
   e. Remove the container; create and start a new one with the updated env.
6. Client JS polls `/aguardar` every 2 s. The portal checks if `http://sala_alunoXX:8443/` responds with HTTP 200 or 302.
7. When code-server is ready, `/aguardar` returns `{ok: true}`.
8. Client enables the "Abrir VS Code" and "Abrir Monitor" buttons. Student clicks to open the workspace or virtual display in a new tab.

#### Why config.yaml is deleted before container recreation

The `linuxserver/code-server` image creates `/config/.config/code-server/config.yaml` on first run and rewrites it on subsequent starts. If a container is recreated with a new `PASSWORD` but the old `config.yaml` remains on the bind-mounted volume, the `bind-addr` in the old file might differ from what the container expects (`0.0.0.0:8443`), making code-server unreachable. Deleting the file before recreation ensures code-server starts cleanly. Password correctness is enforced by the env var, not by config.yaml.

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

- **Container does not exist (`docker.errors.NotFound`).** `iniciar_container` logs an error and returns false. Student sees the loading page for up to 90 s before client-side timeout displays "Falha ao iniciar ambiente."
- **Fast restart exec fails.** Exit code check triggers fallback to full container recreation. The student waits the normal 15–45 s instead of ~1–2 s, but the session is never in an inconsistent state.
- **Container starts but code-server never becomes healthy (90 s client timeout).** Client JS stops polling and shows the error with a "tente novamente" link.
- **Multiple simultaneous starts of the same container.** Docker API serializes container operations. The second `remove()` would fail; the function catches all exceptions and returns false.
- **Student closes browser without logging out.** GC will stop the container after `INATIVIDADE_MINUTOS`. Session remains in `sessoes.json` until expiry.
- **GC thread crashes.** Logged via `app.logger.exception`. The loop's outer try/except keeps it running. If the entire thread dies, containers leak until portal restart.

### Failure Modes

- **Docker socket unreachable.** `docker.from_env()` raises. The portal logs the error and the user sees a generic error.
- **Disk full.** Container start may fail with various errors. Generic error to user.
- **Network missing.** `sala_net` is created by the compose stack. If missing, container start fails.

## Integration Points

- **Authentication:** must succeed before lifecycle activates.
- **Admin Panel:** admin can manually stop or restart any container, bypassing the lifecycle.
- **Auto-Reconnect:** depends on `/ping` to detect that the container was stopped by GC.

## Implementation References

- `portal/app.py:_reiniciar_code_server` — fast restart via docker exec + s6-svc (Path B)
- `portal/app.py:iniciar_container` — full spawn logic with Path A/B/C routing
- `portal/app.py:_apagar_config_yaml` — deletes stale config.yaml before recreation
- `portal/app.py:_senha_config_yaml` — reads config.yaml (retained for diagnostics; not used for auth decisions)
- `portal/app.py:aguardar_code_server` — internal health-check polling
- `portal/app.py:aguardar_env` — `/aguardar` endpoint polled by client JS
- `portal/app.py:conectar` — triggers spawn, renders loading page
- `portal/app.py:parar_container` — stop logic
- `portal/app.py:gc_loop` — idle cleanup loop
- `portal/app.py:ping`, `portal/app.py:heartbeat` — keep-alive endpoints
- `preaquecer.sh` — pre-warm script; containers started here benefit from Path B on login

## Related

- [ADR-0005: On-demand container spawning](../decisions/0005-on-demand-containers.md)
- [ADR-0009: Fast restart via s6-svc](../decisions/0009-fast-restart-s6.md)
- [Feature: Authentication](./authentication.md)
- [Feature: Auto-Reconnect](./auto-reconnect.md)
