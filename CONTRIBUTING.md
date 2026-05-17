# Contribuindo com o Code Sphere

Obrigado pelo interesse em contribuir! Este guia é voltado principalmente para **professores de programação** que querem adaptar, melhorar ou reportar problemas no Code Sphere — mas desenvolvedores experientes também encontrarão aqui tudo que precisam.

---

## O que é e para quem é

O Code Sphere foi criado no contexto do **SENAI** para resolver um problema prático: dar a cada aluno um ambiente Python completo em sala, rodando no navegador, sem instalar nada nos dispositivos dos alunos. Se você é professor e quer usar ou melhorar este projeto para sua turma, você está no lugar certo.

---

## Formas de contribuir

Você não precisa saber programar para contribuir:

| Tipo de contribuição | Como fazer |
|---|---|
| Reportar um bug | Abra uma [issue no GitHub](../../issues) |
| Sugerir uma melhoria | Abra uma issue com o prefixo `[sugestão]` |
| Adaptar para sua escola | Fork + pull request com suas mudanças |
| Melhorar a documentação | Edite arquivos em `docs/` e abra um pull request |
| Compartilhar seu uso | Comente em issues ou abra uma discussion |

---

## Reportando bugs

Antes de abrir uma issue, verifique se o problema já foi relatado. Se não, inclua:

- **O que você esperava que acontecesse**
- **O que aconteceu de fato**
- **Versão do sistema** (`version.json` na raiz do projeto)
- **Saída relevante de logs**, se disponível:

```bash
docker logs sala_portal --tail 50
```

- **Ambiente:** número de alunos, RAM do servidor, Linux distro

Para problemas com containers de alunos específicos:

```bash
docker logs sala_aluno05 --tail 30
```

---

## Sugerindo melhorias

Ao sugerir uma feature, descreva:

1. **O problema pedagógico** que ela resolve (ex: "professores precisam ver os arquivos dos alunos durante a prova")
2. **Como você imagina que funcionaria** do ponto de vista do usuário
3. **O que você acha aceitável sacrificar** em troca (ex: mais complexidade na instalação? maior uso de RAM?)

Sugestões que mantêm os três objetivos centrais do projeto têm maior chance de serem incorporadas:

- Zero instalação nos dispositivos dos alunos
- Um único servidor Linux, sem infraestrutura complexa
- Operação viável em hardware de escola (16 GB RAM, 30 alunos simultâneos)

---

## Configurando o ambiente de desenvolvimento

### Pré-requisitos

- Linux (Ubuntu 22.04+ recomendado — **não use WSL para testes de produção**)
- Docker e Docker Compose v2
- Python 3.12+ (para rodar o portal localmente, se necessário)

### Clonando e subindo o ambiente

```bash
git clone <url-do-repositorio>
cd code-sphere
./setup.sh     # configuração interativa — gera config.env e sobe o ambiente
```

### Estrutura do projeto

```
code-sphere/
├── portal/            ← aplicação Flask (autenticação, painel, ciclo de containers)
│   ├── app.py         ← lógica principal
│   └── templates/     ← HTML das telas
├── traefik/           ← configuração do reverse proxy
├── docs/              ← documentação técnica (arquitetura, ADRs, specs de feature)
├── gerar.sh           ← gera docker-compose.yml e routes.yml a partir de config.env
├── iniciar.sh         ← sobe o ambiente
├── parar.sh           ← desliga tudo
└── config.env         ← configuração principal (não versionar com senhas reais)
```

### Fluxo de desenvolvimento típico

1. Edite `portal/app.py` ou os templates em `portal/templates/`
2. Reconstrua e reinicie apenas o portal:

```bash
docker compose up -d --build portal
```

3. Teste o fluxo de login, troca de senha e painel admin
4. Verifique os logs em tempo real:

```bash
docker logs sala_portal -f
```

---

## Padrões de código

O portal é uma aplicação Flask em arquivo único (`portal/app.py`). Antes de contribuir com código:

- Leia `portal/app.py` por inteiro — ele é pequeno e auto-explicativo
- Mantenha essa característica: **uma feature nova não deve exigir um arquivo novo** se puder ser adicionada no existente sem prejudicar a legibilidade
- Senhas e tokens nunca devem aparecer em logs
- Novas rotas seguem o padrão já existente: autenticação verificada via `@login_required` ou `@admin_required`
- Evite dependências novas sem necessidade; o `requirements.txt` do portal é deliberadamente pequeno

---

## Trabalhando com a documentação

Este projeto segue **Specification-Driven Development (SDD)**: as especificações em `docs/features/` são a fonte de verdade do comportamento esperado, não o código.

Ao modificar ou adicionar uma feature:

1. **Leia a spec da feature** em `docs/features/` antes de tocar no código
2. **Se a spec não existir**, crie uma usando o template em `docs/features/README.md`
3. **Atualize a spec no mesmo commit** que altera o comportamento — spec desatualizada é pior que ausente
4. Para decisões arquiteturais não-óbvias, adicione um ADR em `docs/decisions/` usando o template em `docs/decisions/README.md`

---

## Enviando um pull request

1. Faça fork do repositório
2. Crie uma branch descritiva:
   ```bash
   git checkout -b fix/timeout-gc-containers
   git checkout -b feature/exportar-lista-alunos
   ```
3. Faça commits pequenos e descritivos
4. Se alterou comportamento documentado, atualize a spec em `docs/features/`
5. Abra o pull request descrevendo:
   - **O problema** que resolve ou a melhoria que traz
   - **Como testar** (quais fluxos verificar)
   - **Impacto em recursos** (mais RAM? mais disco? afeta tempo de startup?)

---

## O que não aceitar como contribuição

Para manter o projeto acessível a professores sem equipe de TI dedicada:

- Introdução de bancos de dados relacionais (PostgreSQL, MySQL) para o portal — o estado em JSON é intencional
- Autenticação via LDAP, OAuth ou SSO — fora do escopo deliberado (ver `docs/decisions/0006-argon2-passwords.md`)
- Orquestração multi-servidor (Kubernetes, Swarm) — ver `docs/decisions/0001-single-server-architecture.md`
- Dependências que exijam configuração adicional do professor para instalar

---

## Contato

Dúvidas sobre o projeto ou sobre como adaptá-lo para sua escola:

**João Pedro** — joaoborba.ti@outlook.com

Issues e discussões no repositório são o canal preferido para que outros professores também se beneficiem das respostas.
