#!/usr/bin/env bash
# =============================================================================
# setup.sh - Configuração interativa da Sala de Aula
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

# Cores
BOLD='\033[1m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BLUE='\033[0;34m'; RESET='\033[0m'

ok()     { echo -e "${GREEN}✔${RESET} $*"; }
info()   { echo -e "${BLUE}ℹ${RESET} $*"; }
warn()   { echo -e "${YELLOW}⚠${RESET} $*"; }
erro()   { echo -e "${RED}✖${RESET} $*"; }
titulo() { echo -e "\n${BOLD}${BLUE}$*${RESET}"; printf '%0.s-' $(seq 1 ${#1}); echo; }

# Leitura simples — sem funções complexas
ask() {
    # ask "Pergunta" "padrão" => lê para VAL
    local _prompt="$1"
    local _default="${2:-}"
    if [ -n "$_default" ]; then
        printf "${BOLD}%s${RESET} [padrão: ${YELLOW}%s${RESET}]: " "$_prompt" "$_default"
    else
        printf "${BOLD}%s${RESET}: " "$_prompt"
    fi
    VAL=""
    read -r VAL </dev/tty || true
    [ -z "$VAL" ] && VAL="$_default"
}

ask_pass() {
    printf "${BOLD}%s${RESET}: " "$1"
    PASS=""
    read -rs PASS </dev/tty || true
    echo
}

confirm() {
    printf "${BOLD}%s${RESET} [s/N]: " "$1"
    local r=""
    read -r r </dev/tty || true
    [[ "$r" =~ ^[sS]$ ]]
}

# ── Banner ──────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Sala de Aula Docker — Setup Interativo              ║"
echo "║       VS Code Web para turmas de programação              ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "Este script vai configurar o ambiente e deixar tudo pronto."
echo "Pressione Enter para aceitar os valores padrão."
echo ""

# ── 1. Verificar Docker ──────────────────────────────────────────────────────
titulo "Verificando pré-requisitos"

if ! command -v docker >/dev/null 2>&1; then
    erro "Docker não encontrado. Instale e rode ./setup.sh novamente."
    echo "Guia: https://docs.docker.com/engine/install/ubuntu/"
    exit 1
fi
ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1) encontrado"

if ! docker ps >/dev/null 2>&1; then
    erro "Sem permissão para usar Docker."
    echo "Rode: sudo usermod -aG docker \$USER  (depois faça logout/login)"
    exit 1
fi
ok "Permissão Docker OK"

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"; ok "Docker Compose v2 encontrado"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"; ok "Docker Compose v1 encontrado"
else
    erro "Docker Compose não encontrado."
    echo "Rode: sudo apt-get install docker-compose-plugin"
    exit 1
fi

# ── 2. Turma ────────────────────────────────────────────────────────────────
titulo "Configuração da Turma"

ask "Quantos alunos no total (ambas as turmas)?" "60"
QUANTIDADE_ALUNOS="$VAL"

ask "Máximo de alunos simultâneos?" "30"
SIMULTANEOS="$VAL"

DUAS_TURMAS=false
if confirm "Dividir em Turma A e Turma B?"; then
    DUAS_TURMAS=true
    meio=$(( QUANTIDADE_ALUNOS / 2 ))
    info "Turma A: aluno01–aluno$(printf '%02d' $meio)"
    info "Turma B: aluno$(printf '%02d' $((meio+1)))–aluno$(printf '%02d' $QUANTIDADE_ALUNOS)"
fi

# ── 3. Acesso ────────────────────────────────────────────────────────────────
titulo "Configuração de Acesso"

ask "Porta HTTP do servidor" "80"
PORTA_PUBLICA="$VAL"

ask "Senha inicial para todos os alunos (trocarão no primeiro login)" "trocar123"
SENHA_INICIAL="$VAL"

echo ""
warn "Escolha uma senha de administrador segura (mínimo 8 caracteres)."
SENHA_ADMIN=""
while true; do
    ask_pass "Senha de administrador"
    SENHA_ADMIN="$PASS"
    if [ ${#SENHA_ADMIN} -lt 8 ]; then
        erro "Muito curta. Use pelo menos 8 caracteres."
        continue
    fi
    ask_pass "Confirme a senha"
    [ "$PASS" = "$SENHA_ADMIN" ] && break
    erro "As senhas não coincidem. Tente novamente."
done
ok "Senha de administrador definida."

# ── 4. Recursos ──────────────────────────────────────────────────────────────
titulo "Recursos de Hardware"

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
info "RAM detectada: ${RAM_GB} GB"

RAM_SUGERIDA=$(( (RAM_GB * 1024 * 70 / 100) / SIMULTANEOS ))
[ "$RAM_SUGERIDA" -gt 768 ] && RAM_SUGERIDA=768
[ "$RAM_SUGERIDA" -lt 256 ] && RAM_SUGERIDA=256

ask "Limite de RAM por aluno (MB)" "${RAM_SUGERIDA}m"
LIMITE_MEMORIA="$VAL"

CPUS=$(nproc)
info "CPUs detectadas: ${CPUS}"
CPU_SUGERIDA=$(python3 -c "print(round(min($CPUS*0.7/$SIMULTANEOS, 1.0), 2))" 2>/dev/null || echo "0.5")

ask "Limite de CPU por aluno (núcleos)" "$CPU_SUGERIDA"
LIMITE_CPU="$VAL"

# ── 5. Inatividade ───────────────────────────────────────────────────────────
titulo "Inatividade"

echo "Containers são desligados automaticamente após N minutos sem uso."
echo "O navegador detecta e reconecta automaticamente."
ask "Minutos de inatividade antes de desligar" "60"
INATIVIDADE_MINUTOS="$VAL"

# ── 6. Fuso horário ──────────────────────────────────────────────────────────
TZ_AUTO=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "America/Sao_Paulo")
ask "Fuso horário" "$TZ_AUTO"
TIMEZONE="$VAL"

# ── 7. Cloudflare Tunnel (HTTPS) ─────────────────────────────────────────────
titulo "HTTPS via Cloudflare Tunnel"

echo "Permite acesso HTTPS nos Chromebooks sem precisar de roteador ou domínio."
CLOUDFLARE_TUNNEL=false
CLOUDFLARE_TOKEN=""

if confirm "Ativar HTTPS via Cloudflare Tunnel?"; then
    CLOUDFLARE_TUNNEL=true
    echo ""
    echo "  1) Básico — URL muda a cada reinicialização (sem cadastro)"
    echo "  2) URL fixo — requer conta gratuita na Cloudflare (recomendado)"
    ask "Modo (1 ou 2)" "1"
    if [ "$VAL" = "2" ]; then
        echo ""
        echo "Para obter o token:"
        echo "  1. Acesse dash.cloudflare.com e crie conta gratuita"
        echo "  2. Zero Trust → Networks → Tunnels → Create tunnel"
        echo "  3. Escolha 'Cloudflared', dê um nome, copie o token"
        ask_pass "Token do Cloudflare (Enter para modo básico)"
        CLOUDFLARE_TOKEN="$PASS"
        [ -z "$CLOUDFLARE_TOKEN" ] && warn "Token vazio — usando modo básico"
    fi
    ok "Cloudflare Tunnel ativado"
fi

# ── 8. Resumo ─────────────────────────────────────────────────────────────────
titulo "Resumo"
echo ""
echo "  Alunos:          $QUANTIDADE_ALUNOS total, $SIMULTANEOS simultâneos"
echo "  Duas turmas:     $DUAS_TURMAS"
echo "  Porta:           $PORTA_PUBLICA"
echo "  Senha inicial:   $SENHA_INICIAL"
echo "  RAM por aluno:   $LIMITE_MEMORIA"
echo "  CPU por aluno:   $LIMITE_CPU"
echo "  Timeout:         ${INATIVIDADE_MINUTOS} min"
echo "  Fuso horário:    $TIMEZONE"
echo "  HTTPS Cloudflare: $CLOUDFLARE_TUNNEL"
echo ""

if ! confirm "Confirma e inicia a instalação?"; then
    echo "Cancelado. Rode ./setup.sh novamente."
    exit 0
fi

# ── 9. Grava config.env ───────────────────────────────────────────────────────
titulo "Gravando configurações"

cat > config.env << CONF
# Gerado por setup.sh em $(date '+%Y-%m-%d %H:%M:%S')
QUANTIDADE_ALUNOS=${QUANTIDADE_ALUNOS}
SIMULTANEOS=${SIMULTANEOS}
DUAS_TURMAS=${DUAS_TURMAS}
PORTA_PUBLICA=${PORTA_PUBLICA}
SENHA_INICIAL=${SENHA_INICIAL}
SENHA_ADMIN=${SENHA_ADMIN}
LIMITE_MEMORIA=${LIMITE_MEMORIA}
LIMITE_CPU=${LIMITE_CPU}
INATIVIDADE_MINUTOS=${INATIVIDADE_MINUTOS}
TIMEZONE=${TIMEZONE}
CLOUDFLARE_TUNNEL=${CLOUDFLARE_TUNNEL}
CLOUDFLARE_TOKEN=${CLOUDFLARE_TOKEN}
CONF
ok "config.env gravado"

# ── 10. Gera arquivos dinâmicos ───────────────────────────────────────────────
titulo "Gerando arquivos do ambiente"
./gerar.sh
ok "Arquivos gerados"

# ── 11. Build das imagens ─────────────────────────────────────────────────────
titulo "Construindo imagens Docker"

info "Construindo portal de autenticação..."
$DC build portal
ok "Portal pronto"

info "Construindo imagem dos alunos (Python + Pygame + PostgreSQL)..."
info "Isso pode levar 5-10 minutos na primeira vez..."
docker build -f aluno.Dockerfile -t sala-aluno:latest .
ok "Imagem dos alunos pronta"

# ── 12. Cria containers ───────────────────────────────────────────────────────
titulo "Criando containers dos alunos"

info "Criando $QUANTIDADE_ALUNOS containers (parados, sobem sob demanda)..."
criados=0
for i in $(seq 1 "$QUANTIDADE_ALUNOS"); do
    nome=$(printf "aluno%02d" "$i")
    $DC create "$nome" >/dev/null 2>&1 && criados=$((criados+1)) || true
    [ $(( i % 10 )) -eq 0 ] && info "$i/$QUANTIDADE_ALUNOS processados..."
done
ok "$criados containers criados"

# ── 13. Sobe infraestrutura ───────────────────────────────────────────────────
titulo "Iniciando a sala de aula"

SERVICOS="traefik portal"
[ "$CLOUDFLARE_TUNNEL" = "true" ] && SERVICOS="$SERVICOS cloudflared"
$DC up -d $SERVICOS
sleep 4

# ── 14. Resultado final ───────────────────────────────────────────────────────
IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "IP-DO-SERVIDOR")
[ "$PORTA_PUBLICA" = "80" ] && PORTA_STR="" || PORTA_STR=":${PORTA_PUBLICA}"

echo ""
echo -e "${BOLD}${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  Instalação concluída!                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  ${BOLD}Acesso local (HTTP):${RESET}"
echo "    http://${IP}${PORTA_STR}/"
echo ""
if [ "$CLOUDFLARE_TUNNEL" = "true" ]; then
    echo -e "  ${BOLD}URL HTTPS (Cloudflare):${RESET}"
    echo "    ./url_atual.sh --watch   (aguarda e exibe)"
    echo ""
fi
echo -e "  ${BOLD}Painel do professor:${RESET}"
echo "    http://${IP}${PORTA_STR}/admin"
echo ""
echo -e "  ${BOLD}Primeiro acesso dos alunos:${RESET}"
echo "    Usuário: aluno01 ... aluno${QUANTIDADE_ALUNOS}"
echo "    Senha:   ${SENHA_INICIAL}"
echo ""
echo -e "  ${BOLD}Comandos úteis:${RESET}"
echo "    ./preaquecer.sh turma_a   → aquece antes da aula"
echo "    ./backup.sh               → backup dos trabalhos"
echo "    ./parar.sh                → desliga tudo"
echo ""
