# ADR-0001: Single-Server Architecture

**Status:** Accepted
**Date:** 2026-04-25
**Decision Makers:** Project lead

## Context

The platform must run in school environments where teachers — not DevOps engineers — are responsible for operation. Schools typically have one classroom server (often a repurposed desktop) and no infrastructure team to manage clusters, load balancers, or distributed databases.

Common deployment patterns in modern web applications assume distributed infrastructure: Kubernetes clusters, managed databases, separate file storage, etc. Adopting any of these would make the system inaccessible to its target users.

## Decision

The entire system runs on a single Linux server. All components — reverse proxy, portal, student containers, optional tunnel — execute on the same host. State persists in local files and Docker volumes. There is no horizontal scaling capability and no high-availability story.

The architecture is explicitly designed to be operable by one person who can SSH into a single machine.

## Alternatives Considered

### Kubernetes deployment with helm chart

Pros: industry standard, scales to many schools from one cluster, easier to update.

Rejected because: the target operator does not have Kubernetes expertise, would not have a cluster available, and would not be able to debug failures. The complexity cost vastly exceeds the benefit for a 60-student deployment.

### Cloud-hosted SaaS with multi-tenant backend

Pros: schools wouldn't need any local infrastructure. Updates are centralized.

Rejected because: schools are reluctant to send student data to external services, the project explicitly targets self-hosted operation, and the maintenance burden of running a SaaS is incompatible with the project being a side effort by a teacher.

### Two-server split (orchestration + workloads)

Pros: cleaner separation of concerns, slightly better resource isolation.

Rejected because: doubling the infrastructure footprint to gain marginal benefits is not worth it at this scale. One server is enough for 30 concurrent students.

## Consequences

### Enabled

- A teacher with basic Linux familiarity can install, run, and recover the system using a handful of shell scripts.
- Documentation can describe the entire system without distinguishing components by host.
- Backups, monitoring, and troubleshooting reduce to operations on one machine.
- The same `docker-compose.yml` file describes the complete deployment.

### Prevented

- Cannot scale beyond what one machine can hold (~30 concurrent code-server instances on 16 GB RAM).
- Cannot survive hardware failure without manual recovery from backups.
- Cannot do zero-downtime deployments — restarting the portal interrupts active sessions.

### New problems introduced

- Resource pressure on a single machine forces careful design (see ADR-0005 on on-demand containers).
- The teacher's machine being down means class can't happen.

## References

- [ADR-0005: On-demand container spawning](./0005-on-demand-containers.md) — necessary because of single-server resource constraints
- [Architecture overview](../architecture.md)
