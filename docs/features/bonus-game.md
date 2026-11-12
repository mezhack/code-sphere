# Feature: Bonus Game

**Status:** Implemented
**Owner:** Project lead
**Last Updated:** 2026-11-12

## Context

A reward hidden in the student hub: students who find it and answer a one-word question about the year's content can play a game in the browser. For the teacher it doubles as a low-stakes check of who knows the content, and it must be possible to turn it off instantly when the class needs the network.

How students discover the bonus is deliberately **not documented here**. The trigger lives in `portal/templates/conectar.html`.

The feature is inert on servers where the teacher has not prepared the game data: no container exists, and the trigger does nothing.

## Behavior

### One-time preparation (teacher)

1. `./preparar_jogo.sh <pc-install.tar.gz>` — builds the `sala-jogo` image, extracts the teacher's own PC install of the game, converts it with the port's converter and writes the result to `./jogo-data/` (git-ignored). The game data never enters an image or the repository.
2. Write the questions in `portal-data/eg_perguntas.json` (git-ignored; format in `portal/eg_perguntas.exemplo.json`).
3. `./iniciar.sh` — creates the `sala_jogo` container **stopped**. It does so only if `jogo-data/` holds a converted package.

### Turning it on and off

The admin panel has a **Bônus: ligado/desligado** button (`POST /admin/jogo/ligar|desligar`). It starts or stops the `sala_jogo` container; the container state is the switch. The bonus is off after every `./parar.sh` / `./iniciar.sh` cycle.

Turning it on is refused when there are no questions or when the container does not exist.

### Student flow

1. The student triggers the bonus on `/conectar`.
2. `GET /eg/pergunta` draws a random question and remembers its index in the session. Returns 404 if the student is not logged in, the bonus is off, or there are no questions — in which case the page shows nothing.
3. The student types a one-word answer. `POST /eg/responder` checks it **on the server**; the answers are never sent to the browser.
4. Each drawn question allows a single attempt. A wrong answer draws another question.
5. A correct answer grants a **pass** and shows a link that opens `/jogo/` in a new tab.

### Answer matching

Case, accents and non-alphanumeric characters are ignored: `Herança`, `heranca` and `HERANÇA` match, as do `__init__`, `init` and `init()`. Each question has a list of accepted answers.

### The pass

Traefik's `forwardAuth` middleware asks the portal (`GET /eg/auth`) before serving anything under `/jogo/`, `/vcbr/` or `/vcsky/`. The portal answers 200 only for a student holding a live pass, or for a logged-in admin.

The game tab calls `POST /eg/ping` every 30 seconds, which renews the pass. A pass not renewed for 150 seconds expires, so closing the tab means the next visit needs a new question. Passes live in the portal's memory: restarting the portal or turning the bonus off revokes all of them.

### Admin visibility

Each student row has an **EG?** light:

- **green** — the most recent answer was correct;
- **red** — the student tried and the most recent answer was wrong;
- **grey** — no attempts: the student has not found the bonus.

A **▶** badge next to the light means the student is playing right now (live pass). Clicking the light opens the student's recent answers (`GET /admin/eg/<aluno>`): when, which question, what was typed, right or wrong. The 50 most recent attempts per student are kept in `portal-data/eg_respostas.json`.

The light and badge refresh with the rest of the panel (`/admin/api/stats`, every 30 s).

### Saves

Saved games stay in the student's browser (IndexedDB), on that Chromebook. The game's own page lets students export and import them.

### Inputs

- Student session cookie; the answer as JSON (`{"resposta": "..."}`, truncated to 80 characters).
- `portal-data/eg_perguntas.json`: `[{"pergunta": "...", "respostas": ["...", "..."]}]`.
- `./jogo-data/`: converted game data.

### Outputs

- `portal-data/eg_respostas.json`: `{"aluno01": [{"quando", "pergunta", "resposta", "certa"}]}`.
- The `sala_jogo` container started or stopped.

### Edge Cases

- **Bonus turned off while students play.** Their pass is revoked and the container stops; the game stalls the next time it needs a file from the server.
- **Student opens `/jogo/` directly.** 403 without a live pass.
- **Student edits the questions file index in the cookie.** The session cookie is signed; a forged index is rejected by Flask.
- **Questions file edited while the portal runs.** It is read on every request; no restart needed. An index drawn before the edit that no longer exists returns 404.
- **Background tab.** Chrome throttles timers in hidden tabs to about one per minute, which still renews the pass within its 150-second window.

### Failure Modes

- **`pnpm install` fails during `preparar_jogo.sh`** (network). Re-run the script; nothing is half-installed.
- **The `.tar.gz` is not a PC install.** The converter stops with "this does not look like a Vice City install folder" and `jogo-data/` is not usable; the bonus stays inert.
- **Chromebook runs out of memory.** The game loads its whole data package into RAM. This is a client-side limit the server cannot detect.

## Integration Points

- **Authentication:** every route requires the student session; `/admin/...` routes require the admin session.
- **Admin Panel:** the switch, the EG? column and the report.
- **Traefik:** `jogo-router` and the `jogo-auth` middleware in `routes.yml`, generated by `gerar.sh`.
- **Container Lifecycle:** the bonus does not keep the student's code-server container alive; the hub page's own ping does.

## Implementation References

- `portal/app.py` — section "Bônus": `eg_normalizar`, `eg_pergunta`, `eg_responder`, `eg_auth`, `eg_ping`, `admin_jogo`, `admin_eg`
- `portal/test_eg.py` — runnable check: `docker run --rm sala-portal:latest python test_eg.py`
- `portal/templates/conectar.html` — trigger and question dialog
- `portal/templates/admin_painel.html` — switch, EG? column, report dialog
- `jogo/Dockerfile`, `jogo/code-sphere.patch`, `jogo/nginx.conf` — the game container
- `preparar_jogo.sh` — one-time data conversion
- `gerar.sh` — `jogo` service, routes and middleware

## Related

- [ADR-0012](../decisions/0012-jogo-bonus-dados-no-servidor.md)
- [Feature: Admin Panel](./admin-panel.md)
