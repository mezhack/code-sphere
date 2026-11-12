#!/usr/bin/env bash
# =============================================================================
# preparar_jogo.sh - Prepara o bônus (uma vez por servidor)
#
# Recebe o .tar.gz da SUA instalação de PC do jogo, converte para o formato do
# motor e deixa em ./jogo-data (fora do git). Os dados nunca entram na imagem.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

ARQ="${1:-}"
if [ ! -f "$ARQ" ]; then
    echo "uso: ./preparar_jogo.sh <instalacao-pc.tar.gz>"
    exit 1
fi

echo "==> Construindo imagens do bônus..."
docker build --target build -t sala-jogo-conversor jogo
docker build -t sala-jogo:latest jogo

TMP=$(mktemp -d "$PWD/jogo-origem.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

echo "==> Extraindo $ARQ ..."
tar -xzf "$ARQ" -C "$TMP"

echo "==> Convertendo (alguns minutos)..."
mkdir -p jogo-data
docker run --rm -v "$TMP":/in:ro -v "$PWD/jogo-data":/out \
    sala-jogo-conversor node scripts/convert-pc.mjs /in /out

if [ ! -f portal-data/eg_perguntas.json ]; then
    echo ""
    echo "AVISO: portal-data/eg_perguntas.json não existe. Copie"
    echo "       portal/eg_perguntas.exemplo.json para lá e escreva suas perguntas."
fi

echo ""
echo "Pronto. Rode ./iniciar.sh e ligue o bônus no painel do professor."
