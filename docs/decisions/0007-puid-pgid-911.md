# ADR-0007: PUID/PGID 911:1001 for Student Volumes

**Status:** Accepted
**Date:** 2026-04-28
**Decision Makers:** Project lead

## Context

The student container is based on `linuxserver/code-server`. Inside the container, code-server runs as a non-root user named `abc` with UID 911 and GID 1001 (these are baked into the linuxserver image and are not configurable without rebuilding from scratch).

The bind-mounted student workspace (`./alunos/alunoXX/`) on the host is owned by the user who created it — typically the teacher running the setup script (commonly UID 1000 on a single-user Ubuntu system).

This UID mismatch caused the code-server process to fail with `EACCES: permission denied, mkdir '/config/.config'` because UID 911 inside the container couldn't write to a directory owned by UID 1000 on the host (despite the names "abc" and the teacher's username being unrelated, the file system only sees numeric IDs).

## Decision

The host directories `./alunos/alunoXX/` are explicitly chowned to **UID 911, GID 1001** at setup time and after any operation that recreates them. The setup script and the `gerar.sh` regeneration script both perform this chown.

The PUID/PGID environment variables passed to the linuxserver/code-server container are also set to `911:1001` to match the actual internal user, since some linuxserver images use these to remap permissions but ours treats them as authoritative.

## Alternatives Considered

### Use UID 1000 for everything

Pros: matches the teacher's host UID, no chown needed.

Rejected because: the linuxserver/code-server image hardcodes the `abc` user as UID 911. Overriding requires rebuilding the image from scratch, losing the benefit of using a maintained upstream image.

### Run student containers as root

Pros: no permission issues at all.

Rejected because: students get a shell in the container. Running as root in the container is acceptable from a host-isolation perspective (Docker still enforces boundaries), but it normalizes a bad practice and increases the impact of any container escape.

### Use a Docker named volume instead of bind mount

Pros: Docker manages permissions automatically.

Rejected because: bind mounts are essential for the admin file viewer (`/admin/arquivos/<aluno>`) and for backups (`./backup.sh` simply tars `./alunos/`). Named volumes hide files in `/var/lib/docker/volumes/` where they're awkward to access.

### Use ACLs instead of ownership

Pros: more flexible, allows multiple users to access.

Rejected because: complicates the model and isn't needed. There's exactly one host user (the teacher) and one container user (abc), and they need exactly one mapping.

## Consequences

### Enabled

- code-server starts cleanly without permission errors.
- Files created inside the container appear with consistent ownership on the host (UID 911), making them easy to identify in admin operations.
- Backup and admin file viewer work correctly.

### Prevented

- Cannot easily edit student files from the host as the teacher's normal user (UID 1000). Operations on `./alunos/` typically require `sudo` or membership in GID 1001.
- Cannot use a different version of the linuxserver/code-server image that uses different internal UIDs without revisiting this decision.

### New problems introduced

- **Setup must run chown.** The `setup.sh` and `gerar.sh` scripts both contain `sudo chown -R 911:1001 ./alunos/`. If a teacher creates new student directories outside these scripts, they must remember to chown.

- **Backups preserve UID 911 ownership.** When restoring a backup on a new machine, the chown might need to be re-applied if Docker assigns different IDs.

## References

- [linuxserver/code-server image](https://docs.linuxserver.io/images/docker-code-server)
- `gerar.sh` — contains the chown command at the end
- `setup.sh` — verifies and corrects ownership during installation
