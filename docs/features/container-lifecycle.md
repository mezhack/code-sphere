# Feature: Container Lifecycle

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-04-29

## Context

Student containers are not always running. They're started when needed and stopped when idle, freeing resources for other students. This feature manages that full lifecycle: spawning a fresh container with a unique authentication token, polling its health, and shutting it down after inactivity.

The lifecycle must be invisible to the student. From their perspective, they log in and the workspace appears. They use it, walk away, come back later, and the workspace is back. The mechanics of container start, stop, and restart should never surface as errors.

## Behavior

### Spawn a Container (on login)

#### Path A — container already running with a matching token

1. Student reaches `/conectar`.
2. Portal checks: container `sala_alunoXX` is `running` **and** `sessoes.json` has an entry for this student.
3. Portal reads the effective password from `alunos/alunoXX/.config/code-server/config.yaml` (the file code-server actually uses). If the file doesn't exist, falls back to the container's `PASSWORD` env var.
4. If the effective password matches the session token: reuse the token, return `/conectar` with `aguardando=False`.
5. Client auto-submits the login form after 1.5 s. Done.

#### Path B — container not running (or password mismatch)

1. Student reaches `/conectar`.
2. Container is not running, or the effective password doesn't match the stored token.
3. Portal generates a fresh 32-character random token.
4. Portal saves the token to `sessoes.json` immediately.
5. Portal renders `/conectar` with `aguardando=True` and **returns the response** — the browser now shows the loading page.
6. In a background thread, `iniciar_container` runs:
   a. If the container was running (password mismatch): stop it.
   b. Delete `alunos/alunoXX/.config/code-server/config.yaml` if it exists (forces code-server to create a fresh one using `PASSWORD`).
   c. Read the existing container's configuration (image, hostname, env vars, volumes, network, labels, resource limits) via Docker API.
   d. Remove `PASSWORD` from env list, append `PASSWORD=<new-token>`.
   e. Remove the container; create and start a new one with the updated env.
7. Client JS polls `/aguardar` every 2 s. The portal checks if `http://sala_alunoXX:8443/` responds with HTTP 200 or 302.
8. When code-server is ready, `/aguardar` returns `{ok: true}`.
9. Client auto-submits the login form with the token. code-server authenticates (using the freshly created `config.yaml` that matches `PASSWORD`). Student lands in workspace.

#### Why config.yaml must be deleted

The `linuxserver/code-server` image creates `/config/.config/code-server/config.yaml` **only on first run**. On subsequent starts it reads the existing file and ignores the `PASSWORD` environment variable. If a container is recreated with a new token but the old `config.yaml` remains on the bind-mounted volume, code-server will authenticate against the old password — causing the autologin to fail with a password mismatch error. Deleting the file before recreation ensures code-server always generates a fresh one from the current `PASSWORD` value.

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

- **Container does not exist (`docker.errors.NotFound`).** The container was never created (setup incomplete) or was manually removed. `iniciar_container` logs an error and returns false. Because this runs in a background thread, the student sees the loading page for up to 90 s before the client-side timeout displays "Falha ao iniciar ambiente. Avise o professor."
- **Container starts but code-server never becomes healthy (90 s client timeout).** Client JS stops polling and shows the error with a "tente novamente" link.
- **Multiple simultaneous starts of the same container.** Docker API serializes container operations. The second `remove()` would fail; the function catches all exceptions and returns false.
- **Student closes browser without logging out.** GC will stop the container after `INATIVIDADE_MINUTOS`. Session remains in `sessoes.json` until expiry.
- **GC thread crashes.** Logged via `app.logger.exception`. The thread loop's outer try/except keeps the loop running. If the entire thread dies, containers leak (won't be stopped) until portal restart.
- **Stale `config.yaml` with wrong `bind-addr`.** If a stale config.yaml configures code-server to bind on `127.0.0.1:8080` instead of `0.0.0.0:8443`, the container starts but is unreachable. Deleting config.yaml before recreation (step 6b above) prevents this state.

### Failure Modes

- **Docker socket unreachable.** `docker.from_env()` raises. The portal logs the error and the user sees "Erro ao iniciar seu ambiente."
- **Disk full.** Container start may fail with various errors. Generic error to user.
- **Network creation failure.** `sala_net` is created by the compose stack. If missing, container start fails. Setup script ensures it exists.

## Integration Points

- **Authentication:** must succeed before lifecycle activates.
- **Admin Panel:** admin can manually stop or restart any container, bypassing the lifecycle.
- **Auto-Reconnect:** depends on `/ping` to detect that the container was stopped by GC.

## Implementation References

- `portal/app.py:iniciar_container` — spawn logic (runs in background thread from `/conectar`)
- `portal/app.py:_apagar_config_yaml` — deletes stale config.yaml before recreation
- `portal/app.py:_senha_config_yaml` — reads effective password from config.yaml for mismatch detection
- `portal/app.py:aguardar_code_server` — health-check polling (used internally; client uses `/aguardar`)
- `portal/app.py:aguardar_env` — `/aguardar` endpoint polled by client JS
- `portal/app.py:conectar` — triggers async spawn, renders loading page
- `portal/app.py:parar_container` — stop logic
- `portal/app.py:gc_loop` — idle cleanup loop
- `portal/app.py:ping`, `portal/app.py:heartbeat` — keep-alive endpoints
- `preaquecer.sh` — pre-warm script that starts containers ahead of class

## Related

- [ADR-0005: On-demand container spawning](../decisions/0005-on-demand-containers.md)
- [Feature: Authentication](./authentication.md)
- [Feature: Auto-Reconnect](./auto-reconnect.md)
