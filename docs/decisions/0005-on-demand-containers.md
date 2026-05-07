# ADR-0005: On-Demand Container Spawning

**Status:** Accepted
**Date:** 2026-04-25
**Decision Makers:** Project lead

## Context

A code-server container with Python and Pygame consumes ~400-700 MB of RAM at idle and uses CPU even when no one is interacting (background extension hosts, file watchers). Running 60 such containers simultaneously on the design-target hardware (16 GB RAM) is impossible.

However, in practice, not all 60 students access the system at once. The teacher uses two classes of 30 students each, and within each class, students cycle between writing code and testing — they're not all consuming peak resources simultaneously. The overlap is bounded by class size, not by total student count.

## Decision

Containers are declared but not auto-started. The `docker-compose.yml` uses `profiles: ["manual"]` on student services, which means `docker compose up` does NOT start them. They exist in `created` state and only run when explicitly started.

The portal starts a student's container only when that student logs in. The portal also stops idle containers via a background garbage collector thread, freeing resources for active students.

A `./preaquecer.sh` script lets the teacher start specified containers (one class at a time) ahead of class to avoid first-login latency.

## Alternatives Considered

### Always-on containers

Pros: simpler, no orchestration logic in the portal, no first-login delay.

Rejected because: 60 always-on containers exceed the RAM budget by 3-4x on target hardware. Would force a much more expensive minimum specification.

### Single shared code-server with multiple users

Pros: drastically lower memory footprint. One process serving everyone.

Rejected because: code-server is fundamentally single-user. Multi-user requires a different product (e.g., JupyterHub, Coder Workspaces) which would change the entire architecture and lose the "real VS Code" experience.

### Kubernetes with Horizontal Pod Autoscaler

Pros: industry-standard pattern for elastic workloads.

Rejected because: violates ADR-0001 (single-server simplicity). Also overkill for a deterministic 60-student bound.

### Manual start by teacher each class

Pros: fully predictable, no portal logic needed.

Rejected because: forces the teacher to manage container lifecycle manually for 60 students, which defeats the goal of zero-friction operation. The pre-warm script (`./preaquecer.sh`) is a *complement* to on-demand spawning, not a replacement.

## Consequences

### Enabled

- 60 student accounts on hardware sized for ~30 concurrent users.
- Resources naturally flow to active students.
- Teacher doesn't manage container lifecycle directly.

### Prevented

- Cannot guarantee instant access. First login of the day for any student takes 30-45 seconds while the container starts and code-server initializes. The pre-warm script mitigates this for prepared classes.
- Cannot run long-lived background tasks (e.g., a continuous data sync from a database) in a student's container, since the GC will stop it during idle periods.

### New problems introduced

- **Race condition between container start and code-server readiness.** Originally the portal slept 3 seconds after starting a container, but on slow hardware code-server wasn't ready yet, causing the native password prompt to appear. Solved by polling the container's HTTP port until it actually responds (see [feature: container lifecycle](../features/container-lifecycle.md)).

- **Token synchronization on restart.** Each container start generates a fresh `PASSWORD` env var. When the GC stops a container and the student logs in again, the new token must be propagated. Solved by removing and recreating the container on each start, never reusing it across sessions.

- **Pre-warming is teacher-managed.** A teacher who forgets to pre-warm before class will have students waiting 30-45 seconds on first login. The setup output reminds about this.

## References

- `portal/app.py:iniciar_container` — the on-demand spawn logic
- `portal/app.py:gc_loop` — the idle cleanup logic
- `preaquecer.sh` — the pre-warm script
- [Feature: container lifecycle](../features/container-lifecycle.md)
