#!/usr/bin/env bash
# =============================================================================
# preaquecer.sh - Sobe os containers dos alunos com antecedência
# =============================================================================
# Use este script 10-15 minutos ANTES da aula começar.
# Os containers inicializam em background enquanto você prepara a aula.
# Quando os alunos fizerem login, o portal reutiliza o container já rodando
# — apenas reinicia o processo code-server com o novo token (~1-2 segundos)
# em vez de recriar o container do zero (15-45 segundos).
#
# Uso:
#   ./preaquecer.sh           → aquece todos os alunos
#   ./preaquecer.sh turma_a   → aquece aluno01 a aluno30
#   ./preaquecer.sh turma_b   → aquece aluno31 a aluno60
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")"
source config.env

TURMA="${1:-todos}"

case "$TURMA" in
  turma_a)
    INICIO=1
    FIM=30
    LABEL="Turma A (aluno01–aluno30)"
    ;;
  turma_b)
    INICIO=31
    FIM=$QUANTIDADE_ALUNOS
    LABEL="Turma B (aluno31–aluno${QUANTIDADE_ALUNOS})"
    ;;
  todos)
    INICIO=1
    FIM=$QUANTIDADE_ALUNOS
    LABEL="Todos os alunos (aluno01–aluno${QUANTIDADE_ALUNOS})"
    ;;
  *)
    echo "Uso: $0 [turma_a|turma_b|todos]"
    exit 1
    ;;
esac

echo "==> Pré-aquecendo $LABEL ..."
echo "    (rode isso 10-15 min antes da aula)"
echo ""

iniciados=0
ja_rodando=0
erros=0

for i in $(seq "$INICIO" "$FIM"); do
    nome=$(printf "aluno%02d" "$i")
    container="sala_${nome}"

    status=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null || echo "nao_existe")

    case "$status" in
      running)
        ja_rodando=$((ja_rodando + 1))
        ;;
      created|exited|paused)
        docker start "$container" >/dev/null 2>&1 && \
          iniciados=$((iniciados + 1)) || \
          erros=$((erros + 1))
        ;;
      nao_existe)
        # Container não existe ainda — cria e sobe
        docker compose create "$nome" >/dev/null 2>&1 || true
        docker start "$container" >/dev/null 2>&1 && \
          iniciados=$((iniciados + 1)) || \
          erros=$((erros + 1))
        ;;
    esac

    # Mostra progresso a cada 10 containers
    total_processado=$((iniciados + ja_rodando + erros))
    if [ $((total_processado % 10)) -eq 0 ]; then
        echo "    ... $total_processado containers processados"
    fi
done

echo ""
echo "============================================================"
echo " Pré-aquecimento concluído!"
echo ""
echo " Iniciados agora:    $iniciados"
echo " Já estavam rodando: $ja_rodando"
[ "$erros" -gt 0 ] && echo " Erros:              $erros (rode docker ps para checar)"
echo ""
echo " Os containers estão inicializando em background."
echo " Em 2-3 minutos o code-server de cada aluno estará carregado."
echo ""
echo " Quando os alunos fizerem login, a conexão será quase instantânea:"
echo " o portal reutiliza o container já rodando e troca só o token (~1-2s)."
echo ""
echo " Dica: para confirmar que está tudo no ar:"
echo "   docker ps | grep sala_aluno | wc -l"
echo " (deve mostrar o número de alunos que você aqueceu)"
echo "============================================================"
