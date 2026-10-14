#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if docker compose version >/dev/null 2>&1; then DC="docker compose"
else DC="docker-compose"; fi

echo "==> Parando containers de alunos..."
# Sem aluno ligado o grep não acha nada e sai com 1; com pipefail isso matava o
# script (e o atualizar.sh junto) antes de parar a infraestrutura.
docker ps --format '{{.Names}}' | { grep '^sala_aluno' || true; } | while read -r c; do
    docker stop "$c" 2>/dev/null || true
done

echo "==> Parando infraestrutura..."
$DC down

echo ""
echo "Sala parada. Arquivos dos alunos preservados em ./alunos/"
