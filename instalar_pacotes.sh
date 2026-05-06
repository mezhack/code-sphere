#!/usr/bin/env bash
# instalar_pacotes.sh - Instala pacotes Python em TODOS os containers dos alunos.
# Sobe os containers temporariamente, instala, e deixa o ciclo normal de GC
# desligá-los depois (ou você pode rodar ./parar.sh).
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -eq 0 ]; then
    [ -f requirements.txt ] || {
        echo "Uso: $0 <pacote>   OU   crie requirements.txt"
        exit 1
    }
    pacotes=$(grep -v '^#' requirements.txt | grep -v '^$' | tr '\n' ' ')
else
    pacotes="$*"
fi

[ -z "$pacotes" ] && { echo "Nada a instalar."; exit 0; }

source config.env

echo "==> Pacotes: $pacotes"
echo "==> Iniciando todos os containers para instalar..."

for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "sala_aluno%02d" "$i")
    docker start "$nome" >/dev/null 2>&1 || true
done

sleep 3  # tempo para code-server inicializar

total=0
ok=0
for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "sala_aluno%02d" "$i")
    total=$((total + 1))
    printf "[%d/%d] %s ... " "$i" "$QUANTIDADE_ALUNOS" "$nome"
    if docker exec -u abc "$nome" pip3 install --user --quiet $pacotes 2>/dev/null; then
        echo "ok"
        ok=$((ok + 1))
    else
        echo "FALHOU"
    fi
done

echo ""
echo "Instalados em $ok de $total containers."
echo ""
echo "Os containers continuarão rodando até o timeout de inatividade"
echo "(${INATIVIDADE_MINUTOS} min). Se quiser pará-los agora:   ./parar.sh"
