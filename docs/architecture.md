# Architecture Overview

## What This System Is

Sala de Aula Docker is a self-hosted classroom platform that provides each student with an isolated, browser-accessible Python development environment. The system targets schools where students use Chromebooks or other restricted devices that cannot install development tools locally.

## Core Goals

The system is designed around three constraints that drive every architectural decision:

1. **Zero installation on student devices.** Students access everything through a browser. No admin rights required, no software to install, no configuration on their side.
2. **Single-server deployment.** A teacher should be able to run this on one Linux machine without distributed infrastructure, cloud services beyond optional HTTPS, or DevOps expertise.
3. **Resource-bounded operation.** The system must run 30 concurrent students on commodity hardware (16 GB RAM is the design target), which means containers cannot all run simultaneously.

## High-Level Component Diagram

```
                    ┌─────────────────────────┐
                    │   Student's Browser     │
                    │   (Chromebook etc.)     │
                    └────────────┬────────────┘
                                 │ HTTP / HTTPS
                                 │
                    ┌────────────▼────────────┐
                    │  Cloudflare Tunnel       │  (optional, for HTTPS)
                    │  (cloudflared container) │
                    └────────────┬────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │  Traefik (reverse proxy)│
                    │  Routes /          → portal
                    │  Routes /code/X/   → studentX
                    └─────┬──────────────┬────┘
                          │              │
                ┌─────────▼────┐    ┌────▼─────────────┐
                │ Portal (Flask)│    │ Student Container │
                │ - Auth        │    │ - code-server     │
                │ - Sessions    │    │ - Python+Pygame   │
                │ - Container   │    │ - PostgreSQL      │
                │   lifecycle   │    │ - Persistent vol  │
                └─────────┬─────┘    └───────────────────┘
                          │
                          │ Docker socket
                          │
                ┌─────────▼─────────────┐
                │ Docker Engine          │
                │ (manages all containers)│
                └────────────────────────┘
```

## Component Responsibilities

### Traefik (reverse proxy)

Routes incoming HTTP requests to the correct container based on URL path. Configuration is declarative through Docker labels — containers describe their own routes. This means the portal can spawn student containers dynamically and Traefik picks them up without restart.

Key paths:
- `/` and `/admin` → Portal (Flask)
- `/code/aluno01/` → Student 01's code-server
- `/code/aluno02/` → Student 02's code-server

### Portal (Flask + Gunicorn)

The system's brain. Handles:
- Student authentication (login, password change, session)
- Admin authentication and dashboard
- Starting and stopping student containers via Docker socket
- Session timeout and idle cleanup (garbage collector thread)
- File browsing for the admin (read-only access to student workspaces)
- Version checking against GitHub releases

The portal is the only component that talks to the Docker daemon. Student containers cannot escape into orchestration.

### Student Containers (code-server)

Each student gets one container based on a custom image extending `linuxserver/code-server`. The image adds Python 3, Pygame, PostgreSQL client, and pre-configured VS Code settings (autosave on, fixed font size).

Containers start in `created` state and only run when:
- The student logs in (portal starts the container on demand)
- The teacher pre-warms before class (`./preaquecer.sh`)

When idle for more than `INATIVIDADE_MINUTOS` minutes, the portal's garbage collector stops them. The persistent volume (`./alunos/alunoXX/`) preserves their files across stop/start cycles.

### Cloudflare Tunnel (optional)

When enabled, provides HTTPS access without requiring a public domain, port forwarding, or SSL certificate management. The `cloudflared` container establishes an outbound connection to Cloudflare's edge, exposing the local Traefik through a `*.trycloudflare.com` URL or a fixed domain (when configured with a token).

This is the only way to make the system accessible to managed Chromebooks that block plain HTTP.

## Key Architectural Properties

### Resource oversubscription with on-demand spawning

The system declares 60 student containers in `docker-compose.yml` but only spawns the ones that are actively in use. This is the core technique for fitting 60 students into hardware sized for 30 concurrent users. See ADR-0005 for details.

### Authentication isolation

The portal generates a fresh authentication token every time a student logs in. The token is injected into the student's container via the `PASSWORD` environment variable when the container starts. The portal then auto-submits the login form on the student's behalf, so the student never sees the code-server's native password prompt.

This means even if a student bookmarks `/code/alunoXX/login`, that URL is useless without a fresh token from the portal.

### Stateless portal, persistent students

The portal's state is two JSON files in `portal-data/`:
- `alunos.json` — usernames and Argon2 password hashes
- `sessoes.json` — active session tokens and last-access timestamps

Student work persists in `alunos/alunoXX/workspace/`. These directories are owned by UID 911 (the `abc` user inside `linuxserver/code-server`) and bind-mounted into the containers.

The portal can be rebuilt and restarted without affecting student data or active sessions, as long as the JSON files are preserved.

### Health-checked container startup

When the portal starts a student's container, it does not immediately redirect — it polls the container's HTTP port until it actually responds, with a 45-second timeout. This prevents the race condition where the redirect happens before code-server finishes booting (which would show the native password prompt instead of the workspace).

## Data Flow: Student Login

1. Student visits `/` → portal renders login page.
2. Student submits username and password → portal verifies Argon2 hash from `alunos.json`.
3. If first login, portal redirects to `/trocar-senha` (forced password change).
4. Otherwise, portal generates a 32-character random token.
5. Portal calls Docker API to start the student's container, injecting the token as `PASSWORD`.
6. Portal polls the container's HTTP port until it responds (timeout: 45s).
7. Portal renders `/conectar` page with auto-submit form to `/code/alunoXX/login`.
8. Form submits with the token → code-server authenticates → student lands in their workspace.

## Data Flow: Idle Cleanup

A background thread in the portal runs every 60 seconds:

1. Reads `sessoes.json` and gets current time.
2. For each session, computes time since last access.
3. If any exceed `INATIVIDADE_MINUTOS` minutes, stops the corresponding container and removes the session.

A separate JavaScript ping in the student's browser hits `/ping` every 30 seconds while they're active, refreshing the `last_access` timestamp. This is what keeps containers alive during use.

When a container is stopped by GC and the student tries to interact with it again, the same `/ping` returns `redirect: /conectar`, which restarts the container automatically. The student sees a brief loading screen and continues working.

## What's Intentionally Not Here

Several features were considered and explicitly rejected to keep the system simple:

- **No multi-server clustering.** Single-server only. ADR-0001 explains why.
- **No SSO or LDAP.** Simple username/password from `alunos.json`. ADR-0006 explains the trade-off.
- **No per-student resource quotas beyond memory and CPU.** Disk usage is not enforced.
- **No automatic backups.** A `./backup.sh` script exists but the teacher must run it manually or schedule it.
- **No real-time collaboration between students.** Each workspace is fully isolated.
- **No grading or assignment system.** The platform provides the environment; pedagogy is the teacher's domain.

These are not future features waiting to be added — they are deliberate non-goals.

## Technology Stack

| Layer | Choice | Why |
|-------|--------|-----|
| Container runtime | Docker Engine 24+ | Industry standard, available on all Linux distros |
| Reverse proxy | Traefik v3.6 | Native Docker label-based routing, no config files |
| Portal language | Python 3.12 | Simple, well-known, fits one-file Flask app |
| Portal framework | Flask + Gunicorn | Minimal, no heavy framework needed |
| Password hashing | Argon2 | Modern, memory-hard, the recommended choice |
| Student IDE | code-server (linuxserver/code-server) | Full VS Code in browser, well-maintained image |
| HTTPS (optional) | Cloudflare Tunnel | Only zero-config option for HTTPS in school networks |
| Tunneling protocol | cloudflared | Official Cloudflare client, runs as container |

## Where to Go Next

- To understand a specific design choice: [`decisions/`](./decisions/)
- To implement or modify a feature: [`features/`](./features/)
- To install or operate the system: [`operations/`](./operations/)
