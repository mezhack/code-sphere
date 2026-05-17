# Contributing to Sala de Aula Docker

Obrigado pelo interesse em contribuir! Este projeto nasceu da necessidade real de um professor e cresce melhor quando outros professores, desenvolvedores e agentes de IA colaboram. Este guia explica como fazer isso de forma organizada.

---

## Antes de Começar

Reserve 10 minutos para ler:

1. **[README.md](./README.md)** — o que é o projeto.
2. **[docs/architecture.md](./docs/architecture.md)** — como o sistema funciona em alto nível.
3. **[docs/README.md](./docs/README.md)** — como a documentação está organizada.

Isso evita propostas que conflitam com decisões já tomadas.

---

## Tipos de Contribuição

### 🐛 Reportar um bug

Abra uma **issue** no GitHub usando o template `Bug Report`. Inclua:

- Versão atual (`cat portal/version.json` no servidor).
- Distribuição Linux e versão do Docker (`docker --version`).
- Passos para reproduzir o problema.
- O que você esperava versus o que aconteceu.
- Logs relevantes (`docker logs sala_portal --tail 30`).

Bugs reportados sem reprodução clara ficam parados. Bugs com reprodução são corrigidos muito mais rápido.

### 💡 Sugerir uma feature

Abra uma **issue** com o template `Feature Request`. Antes de codar:

- Verifique se já existe issue ou ADR sobre o tema.
- Descreva o problema que a feature resolve, não a solução em si. (Soluções podem mudar; problemas são mais estáveis.)
- Espere uma resposta antes de começar a implementar. Algumas features fazem sentido pedagogicamente mas não arquiteturalmente, e isso fica mais claro na discussão.

### 📖 Melhorar a documentação

Documentação é tão importante quanto código neste projeto. Correções de erros, exemplos faltando, traduções, ou clarificações são bem-vindas. Pode abrir pull request diretamente sem issue prévia.

### 🔧 Implementar ou corrigir algo

Para mudanças pequenas (correção de typo, bug óbvio): pull request direto.

Para mudanças não-triviais: abra issue primeiro discutindo a abordagem. Isso evita você gastar tempo numa direção que será rejeitada.

---

## Fluxo de Pull Request

### 1. Fork e Clone

```bash
# Faça fork pela interface do GitHub. Depois:
git clone https://github.com/SEU-USUARIO/sala-de-aula-docker.git
cd sala-de-aula-docker
git remote add upstream https://github.com/USUARIO-ORIGINAL/sala-de-aula-docker.git
```

### 2. Crie um Branch

Nunca commite direto no `main`. Sempre crie um branch descritivo:

```bash
git checkout -b feature/suporte-tres-turmas
# ou
git checkout -b fix/login-com-acentos
# ou
git checkout -b docs/troubleshooting-windows
```

### 3. Faça as Mudanças

- Mantenha cada pull request focado em **uma coisa**. PRs que misturam várias mudanças não relacionadas são difíceis de revisar.
- Siga o estilo de código existente. Python: PEP 8. Shell: defensivo (`set -euo pipefail`, aspas em variáveis). Templates: indentação consistente.
- Se a mudança afeta uma feature documentada, **atualize a spec em `docs/features/`** no mesmo commit que o código.
- Se a mudança introduz uma decisão arquitetural não trivial, **adicione um ADR em `docs/decisions/`**.

### 4. Teste

Antes de abrir o PR, confirme:

- O setup interativo ainda funciona (`./setup.sh` em uma máquina limpa).
- O portal sobe sem erros (`docker compose up -d portal && docker logs sala_portal`).
- Um login de aluno funciona end-to-end.
- O painel admin abre e mostra as informações esperadas.

Se a mudança afeta a infraestrutura, teste também:

- Reinício após `./parar.sh && ./iniciar.sh`.
- Pré-aquecimento (`./preaquecer.sh`).

### 5. Commit

Mensagens de commit no padrão **Conventional Commits**:

```
feat: adiciona suporte a três turmas
fix: corrige autenticação com caracteres acentuados
docs: atualiza guia de troubleshooting para Windows
refactor: extrai lógica de health check para função separada
chore: atualiza versão do Traefik para v3.6
```

Prefixos válidos: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `style`.

### 6. Push e Abra o PR

```bash
git push origin feature/suporte-tres-turmas
```

Abra o PR pela interface do GitHub. Use o template fornecido e inclua:

- **O que muda** e **por quê**.
- Link para a issue relacionada (se houver).
- Como testar a mudança.
- Quais specs ou ADRs foram atualizados.

### 7. Revisão

A revisão pode pedir mudanças. Isso não é crítica pessoal — é como o projeto mantém qualidade. Algumas razões comuns:

- Falta de testes ou validação.
- Spec não atualizada para refletir o novo comportamento.
- Conflito com uma decisão arquitetural (ADR).
- Estilo de código inconsistente.

Faça as mudanças, commite no mesmo branch, e o PR atualiza automaticamente.

---

## Diretrizes Específicas

### Para Mudanças no Portal (`portal/app.py`)

- O arquivo é deliberadamente grande para caber em uma leitura. Não fragmente em módulos sem discussão prévia.
- Cada rota deve ter um docstring breve explicando o propósito.
- Operações com Docker API devem ter timeout — containers travados não podem bloquear o portal.
- Mudanças em rotas existentes podem quebrar bookmarks dos professores. Documente isso no PR.

### Para Mudanças nos Scripts (`*.sh`)

- Use `set -euo pipefail` no topo.
- Aspas em todas as expansões de variável (`"$VAR"`, não `$VAR`).
- Mensagens para o usuário em português (o público-alvo é professor brasileiro).
- Detecção de erro deve dizer ao usuário **o que fazer**, não só **o que falhou**.

### Para Mudanças no `gerar.sh`

Esse script gera arquivos a partir do `config.env`. Cuidado especial:

- Mudanças na estrutura do `docker-compose.yml` gerado podem quebrar instalações existentes na próxima vez que `gerar.sh` for executado.
- Se você adicionar uma nova variável ao `config.env`, garanta um valor padrão sensato para instalações antigas que não têm essa variável.

### Para Mudanças na Imagem do Aluno (`aluno.Dockerfile`)

- Cada pacote adicionado aumenta o tamanho da imagem (~5-50 MB cada). Justifique no PR.
- Pacotes que rodam só em parte das aulas talvez não devam estar na imagem base — podem ser instalados pelo aluno quando necessário.
- Quebra de compatibilidade no Dockerfile (e.g., remoção de pacote) deve ser tratada como mudança major.

### Para Mudanças na Documentação

- Documentação técnica (`docs/`) é em inglês.
- Documentação para usuário final (READMEs no diretório principal, mensagens em scripts) é em português.
- Atualize o índice (`docs/README.md`, `docs/decisions/README.md`, `docs/features/README.md`) ao adicionar arquivos novos.
- Mantenha exemplos de código alinhados com o código real. Specs com exemplos quebrados confundem mais que ajudam.

---

## Contribuindo com Agentes de IA

Este projeto foi desenhado para ser legível por agentes de IA. Se você usar um agente (Claude, Copilot, Cursor, ChatGPT, etc.) para gerar contribuições, **a responsabilidade pelo código submetido é sua**, não do agente. Isso significa:

- **Leia e entenda** todo o código gerado antes de submeter. PRs onde fica claro que o autor não entende o que está submetendo serão fechados.
- **Verifique conformidade** com as specs em `docs/features/` e com os ADRs em `docs/decisions/`. Agentes às vezes propõem soluções que conflitam com decisões já tomadas.
- **Teste o código** em um servidor real antes de abrir o PR. Código gerado que nunca foi executado tende a ter bugs sutis.
- **Mantenha o autor humano como responsável**. Não atribua autoria a "Claude" ou outro modelo nos commits — você é o autor; o agente foi ferramenta.

Quando o agente atualizar o código, peça que ele também atualize a spec correspondente. Specs desatualizadas degradam a qualidade do projeto ao longo do tempo.

---

## O Que Não Aceitamos

Algumas categorias de contribuição são rejeitadas por padrão. Isso poupa seu tempo:

### Mudanças que violam decisões arquiteturais documentadas

Se você quer propor que o sistema rode em Kubernetes, leia [ADR-0001](./docs/decisions/0001-single-server-architecture.md) primeiro. Para questionar uma decisão arquitetural, abra issue argumentando contra o ADR — não submeta o código pronto.

### Features pedagógicas

A plataforma fornece o **ambiente** para programação. O **conteúdo** pedagógico (planos de aula, exercícios, sistema de notas, gradebook, etc.) está fora do escopo. Use Google Classroom, Moodle, ou ferramenta similar para isso.

### Dependências pesadas

Adicionar Redis, PostgreSQL, RabbitMQ, ou outras dependências de infraestrutura externa para o portal precisa de justificativa muito forte. O projeto preza simplicidade de instalação.

### Mudanças cosméticas em massa

PRs que reformatam código sem mudar comportamento (alterar todos os espaços, renomear variáveis em massa, etc.) geralmente são rejeitados. Não vale o custo de revisão e o risco de regressões.

### Código sem propósito claro

"Refatoração geral" sem problema concreto sendo resolvido é difícil de avaliar. Diga o que está melhor depois da mudança e por quê.

---

## Reconhecimento

Todas as contribuições aceitas são reconhecidas no `CHANGELOG.md` da release correspondente. Contribuições significativas são também mencionadas no `README.md`.

Não há sistema formal de "manutenedores" neste momento — o projeto é mantido pelo autor original com apoio da comunidade.

---

## Código de Conduta

Seja respeitoso. Este é um projeto educacional construído por um professor para professores. Discussões técnicas são bem-vindas e necessárias, mas comentários depreciativos, ataques pessoais, ou comportamento hostil resultam em remoção da pessoa do projeto.

Em desacordos técnicos: foque no problema, não no proponente. "Essa abordagem tem um problema X" é construtivo. "Quem fez isso não entende o básico" não é.

---

## Dúvidas?

Abra uma **issue** com a label `question`. Não usamos Discord, Slack ou outras plataformas em tempo real — a discussão no GitHub fica registrada e ajuda futuros contribuidores.

Para questões privadas (e.g., relato de vulnerabilidade de segurança), entre em contato direto pelo email no perfil do mantenedor.

---

**Obrigado por contribuir.** Cada melhoria que você propõe pode beneficiar centenas de professores e milhares de alunos que vão usar a plataforma. Isso importa.
