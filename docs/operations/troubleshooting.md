# Troubleshooting

This guide covers known issues and their solutions, organized by symptom.

## Symptom: 404 Not Found at Admin or Portal

**Likely cause:** Traefik can't see the portal. Either the portal isn't running, or Traefik's routing rules are stale.

```bash
# Check both are running
docker ps | grep -E 'sala_traefik|sala_portal'

# Check Traefik logs for errors
docker logs sala_traefik --tail 30
```

If Traefik logs show `client version 1.24 is too old`, the Traefik image is too old for your Docker engine. Fix:

```bash
sed -i 's/image: traefik:v3\.[0-9]*/image: traefik:v3.6/' docker-compose.yml
docker compose up -d --force-recreate traefik
```

If the portal isn't running:

```bash
docker compose up -d --force-recreate portal
```

## Symptom: 502 Bad Gateway After Login

**Likely cause:** the student's container is starting but code-server isn't ready yet, or the container failed to start.

Wait 30 seconds and refresh. If it persists:

```bash
docker logs sala_aluno01 --tail 20
```

Common errors and fixes:

### `EACCES: permission denied, mkdir '/config/.config'`

The workspace directory has wrong ownership. Fix:

```bash
sudo chown -R 911:1001 ~/sala-de-aula/alunos/
docker restart sala_aluno01
```

To fix all students at once:

```bash
sudo chown -R 911:1001 ~/sala-de-aula/alunos/
docker ps --format '{{.Names}}' | grep '^sala_aluno' | xargs -r docker restart
```

See [ADR-0007](../decisions/0007-puid-pgid-911.md) for why UID 911 is required.

### `Container sala_alunoXX não existe`

The container was never created or was manually removed. Recreate:

```bash
docker compose create alunoXX
```

To recreate all missing student containers:

```bash
for i in $(seq 1 60); do
  nome=$(printf "aluno%02d" $i)
  docker compose create "$nome" 2>/dev/null && echo "ok: $nome"
done
```

## Symptom: Student Sees "Welcome to code-server" Password Prompt

**Likely cause:** the portal redirected to the student's container before the auto-login form could submit, OR the container has a stale password from a previous session.

This is the bug that the health-check feature was added to prevent. If it still happens:

```bash
docker restart sala_alunoXX
```

Tell the student to close the tab and log in again from the portal URL (not directly via the `/code/...` URL).

If multiple students see this, the most likely cause is containers created with stale tokens. Recreate them:

```bash
./parar.sh
for i in $(seq 1 60); do
  docker rm -f "sala_$(printf 'aluno%02d' $i)" 2>/dev/null || true
done
sudo chown -R 911:1001 ~/sala-de-aula/alunos/
for i in $(seq 1 60); do
  docker compose create "$(printf 'aluno%02d' $i)" 2>/dev/null
done
./iniciar.sh
```

## Symptom: Admin Panel Loads Forever

**Likely cause:** the panel is making one Docker API call per student to check status. If many calls are slow, the panel hangs.

This was fixed in version 1.0.0 by using a single filtered call. If the symptom recurs, you may have an older portal image. Rebuild:

```bash
cd ~/sala-de-aula
docker compose build portal
docker compose up -d --force-recreate portal
```

## Symptom: Portal Returns Internal Server Error (500)

**Cause:** Python exception in the portal.

```bash
docker logs sala_portal --tail 50
```

Look for the traceback. Common causes:

- **`BuildError: Could not build url for endpoint 'admin_painel'`** — there's a routing inconsistency, usually after a manual edit of `app.py`. Reset to the canonical version (re-extract from the release tarball or pull from git).
- **`PermissionError: [Errno 13] Permission denied: '/data/alunos.json'`** — the `portal-data/` directory has wrong ownership. Fix: `sudo chown -R $USER:$USER ~/sala-de-aula/portal-data/`
- **`docker.errors.DockerException: Error while fetching server API version`** — the portal can't reach the Docker socket. Check that `docker-compose.yml` mounts `/var/run/docker.sock` for the portal service.

## Symptom: Cloudflare Tunnel URL Not Showing

```bash
docker logs sala_cloudflared --tail 30
```

If you see `connection reset by peer` or similar network errors, your network is blocking outbound HTTPS to Cloudflare. The tunnel can't work; use local HTTP fallback (`http://<server-ip>/`).

If the container is running but `url_atual.sh` returns "URL não disponível", wait 30 seconds and try again — cloudflared takes time to register.

## Symptom: `setup.sh` Hangs After First Question

**Cause:** the script can't read from stdin properly.

This was fixed by reading from `/dev/tty` explicitly. If the symptom returns:

```bash
# Make sure it's the latest setup.sh
sed -i 's/\r$//' setup.sh    # remove Windows line endings if any
chmod +x setup.sh
bash setup.sh                 # run with bash explicitly
```

## Symptom: `gerar.sh` Fails with `memory must be a string`

**Cause:** `LIMITE_MEMORIA` in `config.env` doesn't have the `m` suffix.

```bash
grep LIMITE_MEMORIA config.env
# If it shows just a number (e.g., LIMITE_MEMORIA=400), add 'm':
sed -i 's/^LIMITE_MEMORIA=\([0-9]*\)$/LIMITE_MEMORIA=\1m/' config.env
./gerar.sh
```

## Symptom: Multiple Students See Errors at Once

**Cause:** infrastructure-level issue, not per-student.

Check:

```bash
# Are infrastructure containers up?
docker ps | grep -E 'traefik|portal'

# Server resource pressure?
free -h
df -h
docker stats --no-stream
```

If the server is out of memory, stop some containers:

```bash
# Stop all student containers; they'll restart on next login
docker ps --format '{{.Names}}' | grep '^sala_aluno' | xargs -r docker stop
```

## Diagnostics

### Get a Snapshot of System State

```bash
echo "=== Containers ===" && docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' && \
echo "=== Resources ===" && free -h && \
echo "=== Disk ===" && df -h ~ && \
echo "=== Active sessions ===" && cat ~/sala-de-aula/portal-data/sessoes.json 2>/dev/null | head -20
```

### Check Specific Student's State

```bash
ALUNO=aluno15

echo "=== Container ===" && docker ps -a --filter "name=sala_$ALUNO"
echo "=== Logs ===" && docker logs "sala_$ALUNO" --tail 20
echo "=== Workspace ownership ===" && ls -la ~/sala-de-aula/alunos/$ALUNO/
echo "=== In session? ===" && grep -c "$ALUNO" ~/sala-de-aula/portal-data/sessoes.json 2>/dev/null
```

## When in Doubt: Nuclear Option

If something is deeply broken and you're starting class in 5 minutes:

```bash
cd ~/sala-de-aula
./parar.sh
docker ps -a --format '{{.Names}}' | grep '^sala_' | xargs -r docker rm -f
sudo chown -R 911:1001 ./alunos/
./iniciar.sh
```

This stops everything, removes all containers (data is preserved in `./alunos/` and `./portal-data/`), fixes ownership, and restarts. The first login of each student is slow but everything works.

## Reporting an Issue

If none of this helps:

1. Capture diagnostics: `docker ps -a > issue.txt && docker logs sala_portal --tail 100 >> issue.txt 2>&1`
2. Note your version: `cat ~/sala-de-aula/portal/version.json`
3. Open an issue on GitHub with the output and steps to reproduce.
