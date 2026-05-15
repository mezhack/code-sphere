#!/usr/bin/env bash
# Atualiza o code-sphere para a versão mais recente disponível no GitHub.
# Uso: ./atualizar.sh
set -euo pipefail
cd "$(dirname "$0")"

BOLD="\033[1m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"

titulo()  { echo -e "\n${BOLD}==> $*${RESET}"; }
ok()      { echo -e "  ${GREEN}✔ $*${RESET}"; }
aviso()   { echo -e "  ${YELLOW}⚠ $*${RESET}"; }
erro()    { echo -e "  ${RED}✗ $*${RESET}"; exit 1; }

# ── Pré-requisitos ──────────────────────────────────────────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    erro "Este diretório não é um repositório git. Atualização manual necessária."
fi

if ! docker ps >/dev/null 2>&1; then
    erro "Docker não acessível. Rode: sudo usermod -aG docker \$USER"
fi

if docker compose version >/dev/null 2>&1; then DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose"
else erro "Docker Compose não instalado."; fi

# ── Versão atual ────────────────────────────────────────────────────────────
VERSAO_ANTES=$(python3 -c "import json; print(json.load(open('portal/version.json'))['version'])" 2>/dev/null || echo "desconhecida")

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║      Atualização do code-sphere          ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "  Versão instalada: ${BOLD}v${VERSAO_ANTES}${RESET}"

# Verifica se há atualizações
titulo "Verificando atualizações..."
git fetch origin main --quiet
COMMITS_ATRAS=$(git rev-list HEAD..origin/main --count 2>/dev/null || echo "0")

if [ "$COMMITS_ATRAS" = "0" ]; then
    ok "Você já está na versão mais recente (v${VERSAO_ANTES})."
    echo ""
    exit 0
fi

VERSAO_REMOTA=$(git show origin/main:portal/version.json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "nova")
echo "  Nova versão disponível: ${BOLD}v${VERSAO_REMOTA}${RESET} (${COMMITS_ATRAS} commit(s) à frente)"
echo ""
read -rp "  Continuar com a atualização? [s/N] " confirma
[[ "$confirma" =~ ^[Ss]$ ]] || { echo "Atualização cancelada."; exit 0; }

# ── 1. Backup ───────────────────────────────────────────────────────────────
titulo "1/5 — Backup de segurança..."
if bash backup.sh; then
    ok "Backup concluído."
else
    aviso "Backup falhou. Continuar mesmo assim? [s/N]"
    read -rp "  " confirma_backup
    [[ "$confirma_backup" =~ ^[Ss]$ ]] || { echo "Atualização cancelada."; exit 0; }
fi
cp config.env config.env.bak.pre-atualizacao
ok "config.env salvo em config.env.bak.pre-atualizacao"

# ── 2. Para a sala ──────────────────────────────────────────────────────────
titulo "2/5 — Parando a sala..."
bash parar.sh
ok "Sala parada."

# ── 3. Puxa novo código ─────────────────────────────────────────────────────
titulo "3/5 — Baixando atualização..."
git pull origin main
VERSAO_DEPOIS=$(python3 -c "import json; print(json.load(open('portal/version.json'))['version'])" 2>/dev/null || echo "nova")
ok "Código atualizado para v${VERSAO_DEPOIS}."

# ── 4. Regenera configs e reconstrói imagem ─────────────────────────────────
titulo "4/5 — Reconstruindo a plataforma..."
bash gerar.sh
ok "Arquivos de configuração gerados."

$DC build portal
ok "Imagem do portal reconstruída."

# Reconstrói imagem do aluno apenas se o Dockerfile mudou
if git diff "v${VERSAO_ANTES}" HEAD -- aluno.Dockerfile 2>/dev/null | grep -q '^[+-]'; then
    echo "  aluno.Dockerfile foi alterado — reconstruindo imagem dos alunos..."
    docker build -f aluno.Dockerfile -t sala-aluno:latest .
    ok "Imagem dos alunos reconstruída."
else
    ok "Imagem dos alunos sem alteração — pulando rebuild."
fi

# ── 5. Sobe a sala ──────────────────────────────────────────────────────────
titulo "5/5 — Subindo a sala..."
source config.env
SERVICOS="traefik portal"
[ "${CLOUDFLARE_TUNNEL:-false}" = "true" ] && SERVICOS="$SERVICOS cloudflared"
$DC up -d --force-recreate $SERVICOS
ok "Sala no ar."

# ── Resultado ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║   Atualização concluída com sucesso!     ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${RESET}"
echo ""
echo "  ${BOLD}v${VERSAO_ANTES}${RESET} → ${GREEN}${BOLD}v${VERSAO_DEPOIS}${RESET}"
echo ""
echo "  Se algo não funcionar corretamente:"
echo "    git checkout v${VERSAO_ANTES}   # volta ao código anterior"
echo "    cp config.env.bak.pre-atualizacao config.env"
echo "    ./gerar.sh && $DC build portal && ./iniciar.sh"
echo ""
