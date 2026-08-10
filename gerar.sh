#!/usr/bin/env bash
# =============================================================================
# gerar.sh - Gera os arquivos dinâmicos do ambiente
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f config.env ]; then
    echo "ERRO: config.env não encontrado."
    exit 1
fi
# shellcheck disable=SC1091
source config.env

if ! [[ "$QUANTIDADE_ALUNOS" =~ ^[0-9]+$ ]] || [ "$QUANTIDADE_ALUNOS" -lt 1 ]; then
    echo "ERRO: QUANTIDADE_ALUNOS inválido."
    exit 1
fi

echo "==> Gerando ambiente para $QUANTIDADE_ALUNOS alunos"
echo "    Inatividade antes de desligar: ${INATIVIDADE_MINUTOS} min"
echo "    Senha inicial: $SENHA_INICIAL"
echo ""

# -----------------------------------------------------------------------------
# 1. Traefik dinâmico — rotas para os containers dos alunos
# -----------------------------------------------------------------------------
echo "==> Gerando traefik/dynamic/routes.yml ..."
mkdir -p traefik/dynamic
ROUTES="traefik/dynamic/routes.yml"

cat > "$ROUTES" <<'HEADER'
# Rotas Traefik — gerado por gerar.sh.
# As rotas precisam existir mesmo quando o container está parado, por isso
# declaramos aqui em vez de usar labels Docker.

http:
  services:

    portal-svc:
      loadBalancer:
        servers:
          - url: "http://sala_portal:5000"

HEADER

for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    cat >> "$ROUTES" <<SVC

    ${nome}-svc:
      loadBalancer:
        servers:
          - url: "http://sala_${nome}:8443"

    ${nome}-screen-svc:
      loadBalancer:
        servers:
          - url: "http://sala_${nome}:6080"

    ${nome}-audio-svc:
      loadBalancer:
        servers:
          - url: "http://sala_${nome}:6081"
SVC
done

cat >> "$ROUTES" <<'MW_HEADER'

  middlewares:
MW_HEADER

for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    cat >> "$ROUTES" <<MW

    strip-${nome}:
      stripPrefix:
        prefixes:
          - "/code/${nome}"

    strip-screen-${nome}:
      stripPrefix:
        prefixes:
          - "/screen/${nome}"

    strip-audio-${nome}:
      stripPrefix:
        prefixes:
          - "/audio/${nome}"
MW
done

cat >> "$ROUTES" <<'R_HEADER'

  routers:

    portal-router:
      rule: "Path(`/`) || PathPrefix(`/login`) || PathPrefix(`/logout`) || PathPrefix(`/trocar-senha`) || PathPrefix(`/conectar`) || PathPrefix(`/aguardar`) || PathPrefix(`/ping`) || PathPrefix(`/heartbeat`) || PathPrefix(`/admin`) || PathPrefix(`/healthz`) || PathPrefix(`/static`) || PathPrefix(`/changelog`) || PathPrefix(`/about`)"
      entryPoints:
        - web
      priority: 50
      service: portal-svc

R_HEADER

for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    cat >> "$ROUTES" <<ROUTER

    ${nome}-router:
      rule: "PathPrefix(\`/code/${nome}\`)"
      entryPoints:
        - web
      priority: 100
      middlewares:
        - strip-${nome}
      service: ${nome}-svc

    ${nome}-screen-router:
      rule: "PathPrefix(\`/screen/${nome}\`)"
      entryPoints:
        - web
      priority: 100
      middlewares:
        - strip-screen-${nome}
      service: ${nome}-screen-svc

    ${nome}-audio-router:
      rule: "PathPrefix(\`/audio/${nome}\`)"
      entryPoints:
        - web
      priority: 100
      middlewares:
        - strip-audio-${nome}
      service: ${nome}-audio-svc
ROUTER
done

echo "    $QUANTIDADE_ALUNOS rotas"

# -----------------------------------------------------------------------------
# 2. docker-compose.yml
# -----------------------------------------------------------------------------
echo "==> Gerando docker-compose.yml ..."

cat > docker-compose.yml <<COMPOSE_HEAD
# Sala de Aula — gerado por gerar.sh. NÃO EDITE MANUALMENTE.

services:
  # Proxy reverso
  traefik:
    image: traefik:v3.2
    container_name: sala_traefik
    ports:
      - "${PORTA_PUBLICA}:80"
      - "127.0.0.1:8090:8080"   # dashboard Traefik só local
    volumes:
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/dynamic/routes.yml:/etc/traefik/dynamic/routes.yml:ro
    restart: unless-stopped
    networks:
      - sala_net
    depends_on:
      - portal

  # Portal de autenticação (gerencia senhas e ciclo de vida dos containers)
  portal:
    build: ./portal
    image: sala-portal:latest
    container_name: sala_portal
    environment:
      - QUANTIDADE_ALUNOS=${QUANTIDADE_ALUNOS}
      - SENHA_INICIAL=${SENHA_INICIAL}
      - SENHA_ADMIN=${SENHA_ADMIN}
      - INATIVIDADE_MINUTOS=${INATIVIDADE_MINUTOS}
      - TZ=${TIMEZONE}
      - DATA_DIR=/data
      - ALUNOS_DIR=/alunos
    volumes:
      - ./portal-data:/data
      - ./alunos:/alunos
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    networks:
      - sala_net

COMPOSE_HEAD


# Container Cloudflare Tunnel (opcional - ativa com CLOUDFLARE_TUNNEL=true)
if [ "${CLOUDFLARE_TUNNEL:-false}" = "true" ]; then
cat >> docker-compose.yml <<'CLOUDFLARED_TOKEN'
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: sala_cloudflared
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TOKEN}
    restart: unless-stopped
    networks:
      - sala_net
    depends_on:
      - traefik

CLOUDFLARED_TOKEN
else
cat >> docker-compose.yml <<'CLOUDFLARED_ANON'
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: sala_cloudflared
    command: tunnel --no-autoupdate --url http://traefik:80
    restart: unless-stopped
    networks:
      - sala_net
    depends_on:
      - traefik

CLOUDFLARED_ANON
fi
# Containers dos alunos (iniciam parados; portal os sobe sob demanda)
# Usa imagem customizada (aluno.Dockerfile) com Python, Pygame e PostgreSQL.
for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    cat >> docker-compose.yml <<ALUNO
  ${nome}:
    image: sala-aluno:latest
    container_name: sala_${nome}
    hostname: sala_${nome}
    environment:
      - PUID=911
      - PGID=1001
      - TZ=${TIMEZONE}
      - PASSWORD=inicial_sera_substituida_ao_logar
      - DEFAULT_WORKSPACE=/config/workspace
      - PROXY_DOMAIN=/code/${nome}
    volumes:
      - ./alunos/${nome}:/config
      - ./vscode-defaults/settings.json:/home/abc/.local/share/code-server/User/settings.json:ro
    deploy:
      resources:
        limits:
          memory: ${LIMITE_MEMORIA}
          cpus: '${LIMITE_CPU}'
    restart: "no"
    networks:
      - sala_net
    profiles: ["manual"]

ALUNO
done

cat >> docker-compose.yml <<'COMPOSE_TAIL'
networks:
  sala_net:
    name: sala_net
    driver: bridge
COMPOSE_TAIL

echo "    docker-compose.yml com $QUANTIDADE_ALUNOS alunos"

# -----------------------------------------------------------------------------
# 3. Workspaces dos alunos
# -----------------------------------------------------------------------------
echo "==> Preparando workspaces ..."
mkdir -p alunos portal-data

for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    if [ ! -d "alunos/${nome}" ]; then
        mkdir -p "alunos/${nome}/workspace"
        cat > "alunos/${nome}/workspace/LEIA-ME.md" <<WELCOME
# Bem-vindo(a), ${nome}!

Seu ambiente de programação Python está pronto.

## Para começar

1. Crie um arquivo (**File → New File**, ou Ctrl+N) e salve como \`hello.py\`.
2. Escreva:
   \`\`\`python
   print("Oi! Sou ${nome}.")
   \`\`\`
3. Abra um terminal: **Terminal → New Terminal** (ou Ctrl+ \`).
4. Rode com:
   \`\`\`
   python3 hello.py
   \`\`\`

Tudo que você criar aqui fica salvo no servidor da escola e estará disponível
na próxima aula.

Bom estudo!

## Sobre privacidade

Os arquivos que você criar aqui podem ser visualizados pelo professor
como parte do acompanhamento pedagógico — é o equivalente digital de
circular pela sala durante os exercícios.
WELCOME
    fi
done

# Permissões para code-server (roda como UID 1000 no container)
# Garante que o code-server (uid=911, gid=1001) consiga escrever nos workspaces.
# Usa Docker para evitar dependência de sudo no host.
docker run --rm -v "$(pwd)/alunos":/target alpine chown -R 911:1001 /target 2>/dev/null || true

echo ""
echo "============================================================"
echo " Arquivos gerados. Próximo passo:"
echo "    ./iniciar.sh"
echo ""
echo " Alunos farão login no portal usando:"
echo "    Usuário: aluno01, aluno02, ..."
echo "    Senha:   $SENHA_INICIAL  (terão que trocar no primeiro acesso)"
echo ""
echo " Painel do professor:"
echo "    http://IP-DO-SERVIDOR/admin"
echo "    Senha: $SENHA_ADMIN  (edite em config.env antes de usar!)"
echo "============================================================"
