# Installation Guide

This guide covers a fresh installation of the platform on an Ubuntu 22.04 (or compatible) Linux server.

## System Requirements

- **OS:** Ubuntu 22.04+ or other Debian-based distribution
- **CPU:** 4+ cores recommended (8+ for 30 simultaneous students)
- **RAM:** 16 GB minimum, 32 GB comfortable
- **Disk:** 50 GB minimum (Docker images + per-student workspaces)
- **Network:** outbound internet access during setup; same LAN as student devices for local access; outbound HTTPS for Cloudflare Tunnel mode

The system is designed for a single classroom server. Multiple servers or distributed deployment are not supported (see [ADR-0001](../decisions/0001-single-server-architecture.md)).

## Installation in 4 Steps

### 1. Get the Code

```bash
git clone https://github.com/<your-fork>/sala-de-aula-docker.git
cd sala-de-aula-docker
```

### 2. Make Setup Executable

```bash
chmod +x setup.sh
```

### 3. Run Setup

```bash
./setup.sh
```

The script will:
- Verify Docker is installed (offer to install if missing)
- Ask configuration questions (defaults shown for each)
- Build the Docker images (5-10 minutes on first run)
- Create student containers (parked, not running)
- Start infrastructure containers
- Display the URLs to share

See [Feature: Interactive Setup](../features/interactive-setup.md) for details on each question.

### 4. Verify

After setup, the script prints something like:

```
╔═══════════════════════════════════════════════════════════╗
║                  Instalação concluída!                    ║
╚═══════════════════════════════════════════════════════════╝

  Acesso local (HTTP):
    http://192.168.1.41/

  Painel do professor:
    http://192.168.1.41/admin

  Primeiro acesso dos alunos:
    Usuário: aluno01 ... aluno60
    Senha:   trocar123
```

Test by:
1. Visiting `/admin` and logging in with the admin password you set.
2. Creating a test login: visit `/`, log in as `aluno01` with the initial password, change the password when prompted.
3. Confirming VS Code opens. In the integrated terminal, run `python3 --version` — should print Python 3.12.x.

## Optional: Enable HTTPS via Cloudflare Tunnel

If you skipped Cloudflare during setup but want to enable it later:

1. Edit `config.env` and set `CLOUDFLARE_TUNNEL=true`. For fixed URL mode, also set `CLOUDFLARE_TOKEN=<your-token>` (see the Cloudflare Tunnel section below for how to get one).
2. Regenerate: `./gerar.sh`
3. Restart: `./parar.sh && ./iniciar.sh`
4. Get the URL: `./url_atual.sh --watch`

### Getting a Cloudflare Token (fixed URL mode)

1. Sign up at [dash.cloudflare.com](https://dash.cloudflare.com) (free).
2. Go to **Zero Trust → Networks → Tunnels → Create a tunnel**.
3. Choose **Cloudflared** type.
4. Give the tunnel a name (e.g., `sala-de-aula`).
5. On the next screen, copy the token shown (a long `eyJ...` string).
6. Configure a public hostname:
   - Type: HTTP
   - URL: `traefik:80`
7. Save.

Paste the token into `config.env` as `CLOUDFLARE_TOKEN=...`.

## Post-Installation

The system is now running. See [Daily Usage](./daily-usage.md) for typical operations.

## Files Created

After installation, the project directory contains:

```
sala-de-aula-docker/
├── config.env              ← your configuration (edit cautiously)
├── docker-compose.yml      ← generated, do not edit by hand
├── alunos/                 ← student workspaces (preserved across restarts)
│   ├── aluno01/workspace/
│   ├── aluno02/workspace/
│   └── ...
├── portal-data/            ← portal state (alunos.json, sessoes.json)
├── traefik/                ← Traefik configuration
└── vscode-defaults/        ← default VS Code settings injected into student containers
```

The contents of `alunos/` and `portal-data/` should be backed up regularly. They are not in `.gitignore` for backup convenience but should not be committed to a public repo.

## Troubleshooting

If installation fails, see [Troubleshooting](./troubleshooting.md).
