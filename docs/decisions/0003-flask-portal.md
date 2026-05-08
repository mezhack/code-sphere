# ADR-0003: Flask + Gunicorn for the Portal

**Status:** Accepted
**Date:** 2026-04-25
**Decision Makers:** Project lead

## Context

The portal is a small web application: roughly 15 routes, 7 templates, no client-side framework. Its responsibilities are authentication, container lifecycle, session tracking, and an admin dashboard.

The portal needs to be modifiable by a teacher with basic Python knowledge. It also needs to be auditable by AI agents, so the codebase should fit comfortably in a single context window without complex framework abstractions hiding behavior.

## Decision

Use **Flask** as the web framework with **Gunicorn** as the WSGI server. The entire portal lives in one Python file (`portal/app.py`, ~600 lines) plus a folder of Jinja templates.

Single Gunicorn worker with 4 threads. No worker pool, no async runtime, no background job queue beyond a single garbage-collector thread.

## Alternatives Considered

### FastAPI

Pros: modern, async-native, excellent type hints and auto-generated docs.

Rejected because: the portal has no need for async (its hot paths are file I/O and Docker API calls, both synchronous). FastAPI's strengths are wasted here, and async adds complexity for thread-shared state (the GC thread, the in-memory token cache).

### Django

Pros: comprehensive, includes admin panel out of the box, ORM for free.

Rejected because: massive overkill for ~15 routes. Django's conventions (apps, settings.py, migrations) would dwarf the actual application logic. The included admin panel doesn't fit our needs (we built a custom one).

### Plain WSGI without a framework

Pros: zero abstraction, maximum auditability.

Rejected because: even a small app benefits from routing, request parsing, and template rendering. Reimplementing these would add more code than Flask itself.

### Node.js (Express or Fastify)

Pros: lower memory footprint, fast startup.

Rejected because: introduces a second language to the codebase (alongside the shell scripts and the Python in student containers). The savings don't justify the added complexity for the maintainer.

## Consequences

### Enabled

- The entire portal logic is readable in one sitting.
- AI agents can ingest the full file and templates in a single context.
- Adding a new route is one function and one template — no scaffolding ceremony.
- Debugging is direct: a print statement and a `docker logs sala_portal` are enough.

### Prevented

- High concurrency. Single Gunicorn worker handles all 60 students. This is fine because portal interactions are brief (login, redirect, occasional ping) — the heavy work happens in student containers.
- Hot reload in development. The portal is rebuilt and recreated through `docker compose build portal`. For active development, a separate workflow is needed (mount the source as a volume, use `flask run --debug`).

### New problems introduced

- A single worker means a slow Docker API call can briefly block other requests. The container spawn path mitigates this by running `iniciar_container` in a background thread and returning the loading page immediately, so one student's slow container start does not delay other requests.
- Thread-shared state requires careful locking. The persistence functions use a `threading.Lock` for atomic file writes.

## References

- `portal/app.py` — the implementation
- [Flask documentation](https://flask.palletsprojects.com/)
- [Gunicorn settings](https://docs.gunicorn.org/en/stable/settings.html)
