#!/usr/bin/env bash
# resetar_workspace.sh - APAGA os arquivos de um aluno (não mexe na senha).
# Útil se o aluno quebrou o ambiente de jeito irrecuperável.
#
# Para resetar SÓ A SENHA, use o painel admin do portal (http://IP/admin).
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -ne 1 ]; then
    echo "Uso: $0 alunoXX"
    exit 1
fi
aluno="$1"

if [ ! -d "alunos/${aluno}" ]; then
    echo "ERRO: alunos/${aluno} não existe."
    exit 1
fi

echo "Isso vai APAGAR todos os arquivos de ${aluno}."
read -p "Digite 'sim' para confirmar: " confirma
[ "$confirma" != "sim" ] && { echo "Cancelado."; exit 0; }

# Backup antes
mkdir -p backups
backup="backups/antes_reset_${aluno}_$(date +%Y%m%d_%H%M).tar.gz"
tar -czf "$backup" "alunos/${aluno}" 2>/dev/null || true
echo "Backup: $backup"

# Para container se estiver rodando
docker stop "sala_${aluno}" 2>/dev/null || true

# Apaga e recria
rm -rf "alunos/${aluno}"
mkdir -p "alunos/${aluno}/workspace"
cat > "alunos/${aluno}/workspace/LEIA-ME.md" <<WELCOME
# Ambiente reiniciado, ${aluno}

Seu ambiente foi resetado pelo professor.
Tudo que você criar na pasta workspace/ fica salvo daqui pra frente.
WELCOME

chown -R 1000:1000 "alunos/${aluno}" 2>/dev/null || true

echo ""
echo "${aluno} resetado. Senha mantida."
echo "Ele vai subir ambiente novo no próximo login."
