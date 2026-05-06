#!/usr/bin/env bash
# =============================================================================
# url_atual.sh - Mostra o URL HTTPS gerado pelo Cloudflare Tunnel
# =============================================================================
# O Cloudflare Tunnel gera um URL HTTPS automático para o servidor.
# No plano sem conta (modo anônimo), esse URL muda a cada reinicialização.
# Use este script no início de cada aula para descobrir o URL atual.
#
# Uso:
#   ./url_atual.sh
#   ./url_atual.sh --watch   (fica atualizando a cada 5s até encontrar)
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")"

WATCH="${1:-}"

buscar_url() {
    docker logs sala_cloudflared 2>&1 | \
        grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' | \
        tail -1
}

if [ "$WATCH" = "--watch" ]; then
    echo "Aguardando URL do Cloudflare Tunnel..."
    while true; do
        URL=$(buscar_url)
        if [ -n "$URL" ]; then
            break
        fi
        sleep 5
        echo -n "."
    done
    echo ""
else
    URL=$(buscar_url)
fi

if [ -z "$URL" ]; then
    echo ""
    echo "URL ainda não disponível. Possíveis causas:"
    echo "  - O container ainda está iniciando (aguarde 10-15s e tente de novo)"
    echo "  - O container não está rodando: docker ps | grep cloudflared"
    echo "  - Erro de conexão: docker logs sala_cloudflared --tail 20"
    echo ""
    echo "Dica: rode com --watch para aguardar automaticamente:"
    echo "  ./url_atual.sh --watch"
    exit 1
fi

echo ""
echo "============================================================"
echo "  URL HTTPS da sala de aula:"
echo ""
echo "    $URL"
echo ""
echo "  Passe esse endereço para os alunos."
echo "  (muda a cada reinicialização do tunnel)"
echo "============================================================"
echo ""
