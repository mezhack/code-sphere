# Troubleshooting

This guide covers known issues and their solutions, organized by symptom.

## Symptom: 404 Not Found at Admin or Portal

**Likely cause:** Traefik is running but hasn't loaded its routes. Check both containers and whether `routes.yml` is visible inside the Traefik container.

```bash
# Check both are running
docker ps | grep -E 'sala_traefik|sala_portal'

# Check what routes Traefik has loaded (should show 60+ entries)
curl -s http://127.0.0.1:8090/api/http/routers | python3 -c \
  "import json,sys; r=json.load(sys.stdin); print(len(r), 'rotas')"

# Check that routes.yml is visible inside the container
docker exec sala_traefik ls /etc/traefik/dynamic/
```

### routes.yml appears empty inside the container (WSL2)

On WSL2, Docker sometimes sees a bind-mounted directory as empty even though the file exists on the host. Verify:

```bash
# Host has the file:
ls traefik/dynamic/routes.yml

# But container doesn't:
docker exec sala_traefik ls /etc/traefik/dynamic/
```

Fix: ensure `gerar.sh` and `docker-compose.yml` mount the **file**, not the directory:

```yaml
volumes:
  - ./traefik/dynamic/routes.yml:/etc/traefik/dynamic/routes.yml:ro  # correct
# NOT:
#  - ./traefik/dynamic:/etc/traefik/dynamic:ro                        # unreliable on WSL2
```

Then recreate Traefik:

```bash
docker compose up -d --force-recreate traefik
```

### routes.yml doesn't exist

If you cloned fresh and haven't run `./iniciar.sh` yet, the file hasn't been generated:

```bash
./gerar.sh        # generates routes.yml and docker-compose.yml
./iniciar.sh      # builds images and starts everything
```

### Portal isn't running

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
sudo chown -R 911:1001 ~/code-sphere/alunos/
docker restart sala_aluno01
```

To fix all students at once:

```bash
sudo chown -R 911:1001 ~/code-sphere/alunos/
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

**Likely cause:** a stale `config.yaml` in the student's volume is interfering with startup, or the container was started outside the portal (e.g., directly via `docker start`) without the `PASSWORD` env var set.

The `linuxserver/code-server` image reads the `PASSWORD` environment variable injected at container creation via `with-contenv`; this takes priority over any value in `config.yaml`. If the container is recreated by the portal, the new `PASSWORD` is always authoritative. However, a stale `config.yaml` with a mismatched `bind-addr` can prevent code-server from binding to `0.0.0.0:8443`, making it unreachable even if the password is correct.

The portal automatically deletes `config.yaml` before recreating a container. If the prompt still appears:

1. Tell the student to log out and log back in via the portal URL (not via `/code/...` directly).
2. If it persists, from the admin panel click "Reiniciar" for that student's container.

If multiple students see this simultaneously, delete the stale configs and recreate:

```bash
# Delete all stale config.yaml files
find ./alunos -name config.yaml -path '*code-server*' -delete

# Recreate all student containers (data in workspace/ is preserved)
./parar.sh
for i in $(seq 1 60); do
  docker rm -f "sala_$(printf 'aluno%02d' $i)" 2>/dev/null || true
  docker compose create "$(printf 'aluno%02d' $i)" 2>/dev/null
done
./iniciar.sh
```

## Symptom: `/screen/alunoXX/` Shows a Blank Page or "Connection Failed"

**Likely cause:** The virtual display stack (Xvfb → x11vnc → noVNC) inside the container didn't start, or websockify isn't running.

Check whether the processes are running inside the student's container:

```bash
docker exec sala_aluno01 pgrep -a Xvfb
docker exec sala_aluno01 pgrep -a x11vnc
docker exec sala_aluno01 pgrep -a websockify
```

If any are missing, the `/custom-cont-init.d/tela` startup script didn't run. Check container logs:

```bash
docker logs sala_aluno01 --tail 30
```

The most common cause is the container running an **older image** (built before the display stack was added in v1.0.3). Rebuild and recreate:

```bash
docker build -f aluno.Dockerfile -t sala-aluno:latest .
./parar.sh && ./iniciar.sh
```

After the student logs in again, the new container will start the display automatically.

### noVNC page appears but says "noVNC ready. Waiting for host..."

The WebSocket path is wrong — the noVNC `index.html` inside the container isn't computing the path correctly for the Traefik prefix.

Verify the `index.html` was replaced:

```bash
docker exec sala_aluno01 cat /usr/share/novnc/index.html
```

It should contain a `<script>` that redirects to `vnc.html?autoconnect=true&path=...`. If it shows the original noVNC page instead, the image is outdated. Rebuild as above.

## Symptom: The Pygame Zero Window Appears Cut Off in the Monitor

**Cause:** the container is running an image built before v1.0.4. There is no window manager on the virtual display, so SDL places the window at `+590+310`; on a 1280x720 screen an 800x600 game runs off the bottom-right edge and the student sees only its top-left corner. Clicks aimed at the visible part fall outside the window and are ignored.

Check that the centering variable is present:

```bash
docker exec sala_aluno01 printenv SDL_VIDEO_CENTERED
# Should print: 1
```

If it is empty, rebuild the image:

```bash
docker build -f aluno.Dockerfile -t sala-aluno:latest .
```

The portal recreates each student container from the `sala-aluno:latest` tag on the next login, so students pick up the new image without any further step.

See [ADR-0010](../decisions/0010-pygame-zero-sem-window-manager.md) for why centering was chosen over installing a window manager.

## Symptom: The Student's Terminal Fills With `ALSA lib ...` Errors

**Cause:** the container has no sound card, and `pygame.mixer` is falling back to ALSA. The errors are noisy but harmless — the game still runs.

The image sets `SDL_AUDIODRIVER=dummy` to suppress this. Verify:

```bash
docker exec sala_aluno01 printenv SDL_AUDIODRIVER
# Should print: dummy
```

If empty, the container predates v1.0.4 — rebuild as above.

Note that this makes sound a silent no-op, not a working feature: `sounds.foo.play()` succeeds and produces nothing. VNC carries no audio, so sound cannot reach the student by any configuration.

## Symptom: The Game Runs but Feels Choppy

**Cause:** the per-student CPU cap. A Pygame Zero game saturates its quota — unlike ordinary Python exercises, it runs a redraw loop continuously.

Measured on a 6-core/12-thread i7: ~16–23 FPS at `LIMITE_CPU=0.28`, ~39 FPS at `0.5`. The default is `0.5` since v1.0.4.

To change it, edit `LIMITE_CPU` in `config.env` and regenerate. **The student containers must then be recreated** — `./iniciar.sh` only recreates `traefik` and `portal`, and the portal reuses the CPU limit stored in each existing container (`nano_cpus` is copied from the old `HostConfig` on recreate). Editing `config.env` alone changes nothing:

```bash
./gerar.sh
./parar.sh
for i in $(seq 1 60); do
  docker rm -f "sala_$(printf 'aluno%02d' $i)" 2>/dev/null || true
  docker compose create "$(printf 'aluno%02d' $i)" 2>/dev/null
done
./iniciar.sh
```

Student work in `alunos/alunoXX/workspace/` is on a bind mount and survives this.

Note the limit is a ceiling, not a reservation: when the whole class runs games at once, the kernel time-shares and everyone lands below their cap regardless.

## Symptom: `ModuleNotFoundError: No module named 'matplotlib'`

**Not a fault.** matplotlib was removed from the student image in v1.0.4 — see [ADR-0010](../decisions/0010-pygame-zero-sem-window-manager.md). `python3-tk` (tkinter) is still available.

To restore it for a class that needs plots, add `matplotlib` back to the `pip3 install` block in `aluno.Dockerfile`, and — because the display has no window manager — also restore the backend pin so `plt.show()` opens a real window:

```dockerfile
RUN mkdir -p /home/abc/.config/matplotlib && \
    echo "backend: TkAgg" > /home/abc/.config/matplotlib/matplotlibrc
```

TkAgg additionally needs `python3-pil.imagetk` in the apt block. Then rebuild and recreate the containers.

## Symptom: Graphical Program Shows Nothing at All

Check that Xvfb is running (see the section above) and that `DISPLAY` is set:

```bash
docker exec sala_aluno01 printenv DISPLAY
# Should print: :1
```

## Symptom: Admin Panel Loads Forever

**Likely cause:** the panel is making one Docker API call per student to check status. If many calls are slow, the panel hangs.

This was fixed in version 1.0.0 by using a single filtered call. If the symptom recurs, you may have an older portal image. Rebuild:

```bash
cd ~/code-sphere
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
- **`PermissionError: [Errno 13] Permission denied: '/data/alunos.json'`** — the `portal-data/` directory has wrong ownership. Fix: `sudo chown -R $USER:$USER ~/code-sphere/portal-data/`
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
echo "=== Active sessions ===" && cat ~/code-sphere/portal-data/sessoes.json 2>/dev/null | head -20
```

### Check Specific Student's State

```bash
ALUNO=aluno15

echo "=== Container ===" && docker ps -a --filter "name=sala_$ALUNO"
echo "=== Logs ===" && docker logs "sala_$ALUNO" --tail 20
echo "=== Workspace ownership ===" && ls -la ~/code-sphere/alunos/$ALUNO/
echo "=== In session? ===" && grep -c "$ALUNO" ~/code-sphere/portal-data/sessoes.json 2>/dev/null
```

## When in Doubt: Nuclear Option

If something is deeply broken and you're starting class in 5 minutes:

```bash
cd ~/code-sphere    # ou o nome da pasta do projeto
./parar.sh
docker ps -a --format '{{.Names}}' | grep '^sala_' | xargs -r docker rm -f
docker run --rm -v "$(pwd)/alunos":/target alpine chown -R 911:1001 /target
./iniciar.sh
```

This stops everything, removes all containers (data is preserved in `./alunos/` and `./portal-data/`), fixes ownership, and restarts. The first login of each student is slow but everything works.

## Reporting an Issue

If none of this helps:

1. Capture diagnostics: `docker ps -a > issue.txt && docker logs sala_portal --tail 100 >> issue.txt 2>&1`
2. Note your version: `cat ~/code-sphere/portal/version.json`
3. Open an issue on GitHub with the output and steps to reproduce.
