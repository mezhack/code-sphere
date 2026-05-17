# Code Sphere — IDE Online para programacao em rede local

![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)

Ambiente multi-usuário que dá **VS Code Web** (code-server) para cada aluno,
com **portal próprio de autenticação**, **troca de senha obrigatória no
primeiro login** e **desligamento automático de containers ociosos**.

---

## Para que serve

Você tem 60 alunos em duas turmas, mas só 30 usam o ambiente ao mesmo tempo.
Em vez de manter 60 containers rodando 24/7 (desperdício de RAM), este
sistema:

- Declara os 60 alunos com suas identidades fixas.
- Mantém os containers **parados** por padrão.
- Liga automaticamente o container do aluno quando ele faz login.
- Desliga depois de um tempo sem uso (padrão 60 min).
- Cada aluno define uma senha pessoal no primeiro acesso.

---

## Arquitetura

```
  Chromebook do aluno
         │
         ▼
  http://IP-DO-SERVIDOR/
         │
         ▼
   ┌──────────┐      ┌──────────────────┐
   │ Traefik  │ ───► │ Portal (Flask)   │──┐
   │ :80      │      │ - login          │  │
   └──────────┘      │ - troca senha    │  │ sobe
         │           │ - painel prof    │  │ containers
         │           │ - gerencia Docker│  │ sob demanda
         │           └──────────────────┘  │
         │                                  ▼
         └────────────► ┌─────────────────────────┐
           (proxy       │ code-server (um por     │
           /code/alunoNN│  aluno, via UID sala_)  │
                        └─────────────────────────┘
```

**Fluxo de login:**
1. Aluno acessa `http://IP/`, vê a tela de login do portal.
2. Informa usuário (`aluno07`) e senha. Se é o primeiro login, é forçado a
   trocar a senha inicial.
3. Portal valida a senha (hash argon2). Se OK:
   - Inicia o container Docker `sala_aluno07` com um token aleatório como
     senha do code-server.
   - Exibe uma tela de carregamento enquanto o container sobe em background.
     O navegador faz polling em `/aguardar` e entra automaticamente no
     code-server assim que ele responde.
4. A cada 30 segundos, o navegador do aluno faz um ping silencioso ao portal
   (`/ping`) marcando atividade.
5. Se passam 60 minutos sem ping, o garbage collector do portal
   desliga o container do aluno automaticamente.

**O aluno nunca conhece a senha do code-server.** Ele só conhece a senha
do portal, que ele mesmo escolheu.

---

## Pré-requisitos

- Linux (Ubuntu 22.04+ recomendado). Não use WSL para produção.
- Docker e Docker Compose v2.
- Para 30 alunos simultâneos: **16 GB de RAM** (mínimo), 4 núcleos, 20 GB livres.

### Instalando Docker no Ubuntu

```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER
# Faça logout/login para aplicar a permissão de grupo
```

Teste: `docker ps` (precisa listar sem erro).

---

## Primeira execução

### 1. Execute 'setup.sh'

**Obrigatório:** troque `SENHA_ADMIN` para algo que só você saiba.

```ini
QUANTIDADE_ALUNOS=60
SIMULTANEOS=30          # máximo de alunos usando ao mesmo tempo
DUAS_TURMAS=false       # true divide em Turma A e Turma B
PORTA_PUBLICA=80
SENHA_INICIAL=trocar123              # senha que TODOS começam com
SENHA_ADMIN=sua_senha_de_professor   # definida interativamente pelo setup.sh
LIMITE_MEMORIA=256m
LIMITE_CPU=0.5
INATIVIDADE_MINUTOS=60
TIMEZONE=America/Sao_Paulo
CLOUDFLARE_TUNNEL=false
```

### 2. Gere os arquivos

```bash
./gerar.sh
```

Isso cria `docker-compose.yml`, `traefik/dynamic/routes.yml`, e as pastas
`alunos/alunoNN/` (60 ao total).
Se executou 'setup.sh', não é necessário esse passo.

### 3. Suba a sala

```bash
./iniciar.sh
```

**Primeira execução baixa imagens** (Traefik, Python, code-server) e
**constrói a imagem do portal** — pode levar 3-5 minutos.

### 4. Distribua senhas aos alunos

Você avisa cada aluno:

- **URL:** `http://IP-DO-SERVIDOR/`
- **Usuário:** seu `alunoNN` (aluno01, aluno02, ...)
- **Senha inicial:** a que você colocou em `SENHA_INICIAL` (ex: `trocar123`)
- **Instrução:** "no primeiro login você vai escolher uma senha pessoal"

Como `SENHA_INICIAL` é a mesma para todos e força troca no primeiro login,
não tem risco real: se alguém tentar entrar antes do dono, o dono vai ver
"senha atual incorreta" na hora de trocar e te avisa.

---

## Operação diária

### Ligar / desligar a sala

```bash
./iniciar.sh   # sobe Traefik + Portal
./parar.sh     # desliga tudo (containers de aluno também)
```

Entre aulas, você pode deixar ligado 24/7 — os containers de alunos se
autogerenciam e só consomem RAM quando alguém está usando.

### Painel do professor

Acesse `http://IP-DO-SERVIDOR/admin`, use a senha de `SENHA_ADMIN`.

Lá você consegue:
- Ver todos os alunos e quem está online agora.
- **Resetar a senha** de um aluno individual (volta para a senha inicial,
  força troca no próximo login).
- **Parar o container** de um aluno (útil se travou).
- **Resetar todas as senhas** em bloco (início de semestre).

### Backup

Rode semanalmente:

```bash
./backup.sh
```

Gera `.tar.gz` em `./backups/` com workspaces dos alunos + banco de senhas.

### Resetar workspace de um aluno

Se o aluno quebrou algo de jeito irrecuperável no ambiente dele:

```bash
./resetar_workspace.sh aluno05
```

Isso **apaga os arquivos** de `aluno05` (com backup automático antes).
A senha dele é preservada.

Para resetar só a senha (o comum), use o painel admin em `/admin`.

### Instalar biblioteca Python em todos os ambientes

Quando Pygame entrar no plano de aula, ou qualquer outra lib:

```bash
./instalar_pacotes.sh pygame
```

Ou edite `requirements.txt` e rode `./instalar_pacotes.sh` sem argumentos.

---

## Como os alunos usam

### No primeiro dia

1. Aluno abre no Chromebook: `http://IP-DO-SERVIDOR/`
2. Digita usuário (`aluno05`) e senha inicial (`trocar123`).
3. Sistema obriga a escolher uma nova senha pessoal.
4. Depois da troca, é redirecionado automaticamente para o VS Code Web dele.

### Nos dias seguintes

1. Aluno abre `http://IP-DO-SERVIDOR/`
2. Informa usuário e sua senha pessoal.
3. Cai direto no VS Code, com os arquivos da aula anterior.

### Se o aluno esquecer a senha

1. Aluno avisa o professor.
2. Professor entra em `/admin`, resetar senha de `alunoNN`.
3. Aluno entra com a senha inicial (`trocar123`) e é forçado a escolher
   nova senha pessoal.

### Para rodar Python

No code-server, **Terminal → New Terminal** e digitar:

```bash
python3 nome_do_arquivo.py
```

`input()` funciona normalmente no terminal integrado.

---

## Estrutura de arquivos

```
code-sphere/
├── config.env                    ← configuração principal (gerado pelo setup.sh)
├── setup.sh                      ← configuração interativa (execute primeiro)
├── gerar.sh                      ← regenera docker-compose.yml e routes.yml
├── iniciar.sh                    ← sobe a sala
├── parar.sh                      ← para a sala
├── atualizar.sh                  ← atualiza o sistema para nova versão
├── preaquecer.sh                 ← sobe containers antes da aula começar
├── backup.sh                     ← backup dos workspaces
├── resetar_workspace.sh          ← apaga dados de um aluno
├── instalar_pacotes.sh           ← instala libs Python em todos
├── url_atual.sh                  ← exibe URL do Cloudflare Tunnel ativo
├── aluno.Dockerfile              ← imagem dos containers dos alunos
├── requirements.txt              ← libs Python pré-instaladas nos containers
│
├── portal/                       ← aplicação Flask de autenticação
│   ├── app.py                    ←   lógica principal
│   ├── Dockerfile
│   ├── requirements.txt
│   └── templates/                ←   HTML das telas
│
├── traefik/
│   ├── traefik.yml               ←   config estática do Traefik
│   └── dynamic/routes.yml        ←   GERADO — rotas dos alunos
│
├── docker-compose.yml            ← GERADO — sobe tudo
│
├── alunos/                       ← GERADO — dados persistentes
│   ├── aluno01/workspace/
│   ├── aluno02/workspace/
│   └── ...
│
├── portal-data/                  ← GERADO — banco de senhas (hash)
│   ├── alunos.json
│   └── sessoes.json
│
└── backups/                      ← GERADO pelos scripts de backup
```

---

## Segurança

- Senhas dos alunos são **hasheadas com argon2** antes de salvar.
- O token de sessão do code-server é **regenerado a cada login novo**.
- A rede interna dos containers é isolada (bridge Docker).
- **Porém:** este sistema foi projetado para **rede local de escola**, HTTP
  puro. Se você for expor à internet, precisa adicionar HTTPS (Let's
  Encrypt via Traefik) e revisar a política de senhas. Me avise se for
  esse o caso.

---

## Solução de problemas

### "Erro ao iniciar seu ambiente"

O portal não conseguiu subir o container. Veja logs:

```bash
docker logs sala_portal --tail 50
```

Causas comuns:
- Socket do Docker não montado (verifique o volume em docker-compose.yml).
- Permissão no socket (usuário `docker` precisa estar no grupo).
- Container `sala_alunoNN` não existe (rode `./gerar.sh` de novo).

### Aluno vê "502 Bad Gateway" depois do login

O container do aluno subiu mas o code-server ainda está inicializando.
O auto-login tem delay de 3s, mas em máquina lenta pode não bastar.
Aluno só precisa clicar "Atualizar" uma vez.

Se acontecer sempre, aumente o delay em `portal/templates/conectar.html`
(procure `3000` no JS e troque para `5000`).

### Container do aluno não desliga sozinho

O garbage collector roda a cada 60s. Se não está desligando, pode ser:
- Navegador do aluno ainda aberto mandando heartbeat.
- Bug no GC. Veja logs: `docker logs sala_portal | grep gc`.

Force parada pelo painel admin: `/admin`, botão "Parar".

### Permissões de arquivo

Se os arquivos do aluno aparecem como "read-only" ou não salvam, rode:

```bash
sudo chown -R 1000:1000 alunos/ portal-data/
```

### Porta 80 em uso

Edite `config.env`: `PORTA_PUBLICA=8080`, rode `./gerar.sh` e
`./iniciar.sh`. Alunos acessam `http://IP:8080/`.

### Tudo está muito lento

Confira `docker stats`. Se RAM no teto, reduza `LIMITE_MEMORIA` em
`config.env` e rode `./gerar.sh` novamente.

---

## Para colegas professores com hardware mais fraco

Este sistema foi calibrado para rodar em 16 GB. Para 8 GB:

1. Reduza `LIMITE_MEMORIA=256m` em `config.env`.
2. Reduza `QUANTIDADE_ALUNOS` se sua turma é menor.
3. Reduza `INATIVIDADE_MINUTOS=15` para liberar RAM mais rápido.

Com esses ajustes, funciona confortável com 20 alunos simultâneos em 8 GB.
# code-sphere
# code-sphere
