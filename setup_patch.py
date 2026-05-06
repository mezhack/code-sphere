content = open("setup.sh").read()

# 1. Adicionar pergunta Cloudflare após fuso horário (antes do resumo)
cloudflare_section = '''
# ── 7. HTTPS via Cloudflare Tunnel ────────────────────────────────────────
titulo "HTTPS via Cloudflare Tunnel"

echo "Os Chromebooks da escola bloqueiam HTTP (não seguro)."
echo "O Cloudflare Tunnel cria um endereço HTTPS gratuito sem precisar de"
echo "roteador, domínio ou certificado. Requer apenas acesso à internet."
echo ""
CLOUDFLARE_TUNNEL=false
CLOUDFLARE_TOKEN=""

if confirmar "Ativar HTTPS via Cloudflare Tunnel?"; then
    CLOUDFLARE_TUNNEL=true
    echo ""
    echo "Modo de uso:"
    echo "  1) Básico (URL muda a cada reinicialização — sem cadastro)"
    echo "  2) URL fixo (requer conta gratuita na Cloudflare — recomendado)"
    echo ""
    perguntar "Modo (1 ou 2)" "1"
    MODO_CF="$RESPOSTA"
    if [ "$MODO_CF" = "2" ]; then
        echo ""
        echo "Para obter o token de URL fixo:"
        echo "  1. Acesse https://dash.cloudflare.com e crie uma conta gratuita"
        echo "  2. Vá em Zero Trust → Networks → Tunnels → Create tunnel"
        echo "  3. Escolha 'Cloudflared', dê um nome ao tunnel"
        echo "  4. Copie o token exibido e cole aqui"
        echo ""
        perguntar_senha "Token do Cloudflare Tunnel (deixe vazio para modo básico)"
        CLOUDFLARE_TOKEN="$RESPOSTA"
        [ -z "$CLOUDFLARE_TOKEN" ] && MODO_CF="1" && warn "Token vazio — usando modo básico"
    fi
    [ "$MODO_CF" = "1" ] && info "Modo básico: URL será exibido com ./url_atual.sh após iniciar"
    ok "Cloudflare Tunnel ativado"
fi

'''

# Inserir antes do "── 7. Resumo"
old = "# ── 7. Resumo e confirmação"
new = cloudflare_section + "# ── 8. Resumo e confirmação"
content = content.replace(old, new)

# 2. Atualizar numeração das seções seguintes
content = content.replace("# ── 8. Grava config.env", "# ── 9. Grava config.env")
content = content.replace("# ── 9. Gera arquivos", "# ── 10. Gera arquivos")
content = content.replace("# ── 10. Build das imagens", "# ── 11. Build das imagens")
content = content.replace("# ── 11. Cria containers", "# ── 12. Cria containers")
content = content.replace("# ── 12. Sobe a infraestrutura", "# ── 13. Sobe a infraestrutura")
content = content.replace("# ── 13. Resultado final", "# ── 14. Resultado final")

# 3. Adicionar CLOUDFLARE_TUNNEL no config.env gerado (antes do CONF final)
old_conf = "TIMEZONE=${TIMEZONE}\nCONF"
new_conf = """TIMEZONE=${TIMEZONE}
CLOUDFLARE_TUNNEL=${CLOUDFLARE_TUNNEL}
CLOUDFLARE_TOKEN=${CLOUDFLARE_TOKEN}
CONF"""
content = content.replace(old_conf, new_conf)

# 4. Subir cloudflared junto com infra
old_up = '$DC up -d traefik portal'
new_up = '''SERVICOS="traefik portal"
[ "${CLOUDFLARE_TUNNEL:-false}" = "true" ] && SERVICOS="$SERVICOS cloudflared"
$DC up -d $SERVICOS'''
content = content.replace(old_up, new_up)

# 5. Mostrar URL Cloudflare no resultado final
old_result = '"   ./preaquecer.sh turma_a   → aquece containers 15min antes da aula"'
new_result = '''"   ./preaquecer.sh turma_a   → aquece containers 15min antes da aula"

if [ "${CLOUDFLARE_TUNNEL:-false}" = "true" ]; then
echo ""
echo -e "  ${BOLD}URL HTTPS (Cloudflare Tunnel):${RESET}"
echo "    ./url_atual.sh --watch   (aguarda e exibe o URL)"
echo "    (passe esse URL para os alunos no início de cada aula)"
fi'''
content = content.replace(old_result, new_result)

open("setup.sh", "w").write(content)
print("OK")
