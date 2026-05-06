#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f docker-compose.yml ]; then
    echo "ERRO: rode ./gerar.sh primeiro."
    exit 1
fi

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else echo "ERRO: Docker Compose não instalado."; exit 1; fi

if ! docker ps >/dev/null 2>&1; then
    echo "ERRO: Docker não acessível. Rode: sudo usermod -aG docker \$USER"
    exit 1
fi

source config.env

echo "==> Construindo imagem do portal..."
$DC build portal

echo "==> Construindo imagem dos alunos (Python + Pygame + PostgreSQL)..."
echo "    (primeira vez demora 5-10min)"
docker build -f aluno.Dockerfile -t sala-aluno:latest .

echo "==> Subindo infraestrutura..."
SERVICOS="traefik portal"
[ "${CLOUDFLARE_TUNNEL:-false}" = "true" ] && SERVICOS="$SERVICOS cloudflared"
$DC up -d $SERVICOS

sleep 4
$DC ps

ip_local=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "IP-DO-SERVIDOR")
[ "${PORTA_PUBLICA:-80}" = "80" ] && porta_str="" || porta_str=":${PORTA_PUBLICA}"

echo ""
echo "============================================================"
echo " Sala no ar!"
echo ""
echo " Acesso local (HTTP):"
echo "   http://${ip_local}${porta_str}/"
echo ""

if [ "${CLOUDFLARE_TUNNEL:-false}" = "true" ]; then
    echo " Acesso HTTPS via Cloudflare Tunnel:"
    echo "   (aguarde 10-15 segundos para o tunnel conectar)"
    echo "   ./url_atual.sh --watch"
    echo ""
fi

echo " Painel do professor:"
echo "   http://${ip_local}${porta_str}/admin"
echo ""
echo " Para parar: ./parar.sh"
echo "============================================================"
