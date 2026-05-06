#!/usr/bin/env bash
# backup.sh - Backup dos workspaces e do banco de senhas.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d alunos ]; then
    echo "Nada para fazer backup."
    exit 1
fi

mkdir -p backups
data=$(date '+%Y-%m-%d_%H%M')
arquivo="backups/backup_${data}.tar.gz"

echo "==> Criando $arquivo ..."

# Inclui workspaces E portal-data (para preservar senhas trocadas).
# Exclui caches e config interna do code-server que são regeneráveis.
tar -czf "$arquivo" \
    --exclude='alunos/*/.config' \
    --exclude='alunos/*/.cache' \
    --exclude='alunos/*/.local' \
    --exclude='alunos/*/.vscode' \
    alunos/ portal-data/ 2>/dev/null

tamanho=$(du -h "$arquivo" | cut -f1)
echo ""
echo "Backup: $arquivo ($tamanho)"
echo ""
echo "Para restaurar em outro servidor:"
echo "    tar -xzf $arquivo"
