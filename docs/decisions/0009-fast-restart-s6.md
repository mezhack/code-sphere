# ADR-0009: Fast Restart via s6-svc for Pre-warmed Containers

**Status:** Accepted  
**Date:** 2026-05-11  
**Owner:** Project lead

## Context

`preaquecer.sh` was designed to reduce student login time by starting containers ahead of class. The intention was that the portal would detect the running container and reuse it rather than recreating from scratch.

However, the original implementation did not work as intended: every login still triggered a full container recreation (Path C). The root cause was a password mismatch. When `preaquecer.sh` starts a container, it uses whatever `PASSWORD` env var was baked in at container creation time (a placeholder like `inicial_sera_substituida_ao_logar`). When a student logs in, the portal generates a fresh 32-character token that doesn't match, so the container is recreated instead of reused. The pre-warming provided no benefit.

The problem required two things: (1) a way to update the token inside a running container without recreating it, and (2) a way to restart only the code-server process so it picks up the new token.

## Decision

Use `docker exec` to update the authentication token and restart only the code-server process inside the running container:

1. Overwrite `/var/run/s6/container_environment/PASSWORD` with the new session token via `docker exec ... bash -c "printf '%s' '<token>' > /var/run/s6/container_environment/PASSWORD"`.
2. Restart the code-server process via `docker exec ... s6-svc -r /run/service/svc-code-server`.

Both exec calls check the exit code. Any non-zero exit triggers fallback to full container recreation (Path C). The student always lands in a working workspace — the only difference is whether it takes ~1–2 seconds (fast restart) or 15–45 seconds (full recreate).

## Critical Finding: PASSWORD env var takes priority over config.yaml

During investigation, it was confirmed (via testing) that the `PASSWORD` environment variable injected at container creation takes priority over any value set in `config.yaml` inside the `linuxserver/code-server` image.

The image's run script reads `$PASSWORD` via `with-contenv` from `/var/run/s6/container_environment/PASSWORD`. If that file is present and non-empty, code-server uses it — regardless of what `config.yaml` says. The `config.yaml` is only consulted when no `PASSWORD` env var is set.

This is the opposite of what the original documentation stated. The implication is:

- Overwriting `/var/run/s6/container_environment/PASSWORD` is sufficient to change the authentication token for the next code-server startup.
- `config.yaml` does not need to be written or read for auth purposes. It is deleted before container recreation only to avoid `bind-addr` mismatches (see [Feature: Container Lifecycle](../features/container-lifecycle.md)).

## Mechanism: s6-overlay and with-contenv

`linuxserver/code-server` uses [s6-overlay](https://github.com/just-containers/s6-overlay) as its init system. Environment variables for supervised services are stored as files in `/var/run/s6/container_environment/`. The `with-contenv` wrapper reads these files and injects them into the environment of each service process at startup.

This means:
- `/var/run/s6/container_environment/PASSWORD` is the live source of the `PASSWORD` variable for any process launched by s6 after creation time.
- Writing a new value to this file and then restarting the service (`s6-svc -r`) causes the new value to take effect immediately, without recreating the container.
- The Docker `inspect` env list (from container creation) is not updated — it still shows the original placeholder. The portal reads the effective password by exec-ing into the container and reading the file directly, not by inspecting container metadata.

## Consequences

- **Positive:** Students with pre-warmed containers log in in ~1–2 seconds instead of 15–45 seconds. `preaquecer.sh` is now genuinely useful.
- **Positive:** Container filesystem state (open files, extensions, in-memory state) is preserved across fast restarts.
- **Negative:** The `docker exec` approach requires the container to be healthy enough to execute commands. If the container is in a degraded state, both exec calls may fail, triggering the full recreate fallback.
- **Neutral:** The original `_senha_config_yaml` helper function is retained for diagnostic purposes but is no longer used in authentication decisions.

## Alternatives Considered

### Recreate with pre-generated token
Generate the session token before starting the container in `preaquecer.sh`, store it somewhere, and have the portal reuse it. Rejected: this would require `preaquecer.sh` to write to `sessoes.json`, coupling the warm-up script to the portal's session state. It would also leave dangling sessions if a class never starts.

### Shared volume for token exchange
Write the token to a file on the student's bind-mounted volume; have code-server read it via a startup hook. Rejected: requires modifying the container image and adds a custom secret-exchange mechanism with no clear advantage over the s6 env var approach.

### Docker container update API
Use `docker update` or recreate with `docker rename`. Rejected: there is no Docker API to update a running container's environment variables. `docker update` only supports resource limits (CPU, memory).

## Related

- [Feature: Container Lifecycle](../features/container-lifecycle.md)
- [ADR-0005: On-demand container spawning](./0005-on-demand-containers.md)
