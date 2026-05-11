"""Portal de acesso da sala de aula."""
from __future__ import annotations
import json, os, secrets, string, threading, time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
import docker
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for, abort

DATA_DIR            = Path(os.environ.get("DATA_DIR", "/data"))
ALUNOS_FILE         = DATA_DIR / "alunos.json"
SESSOES_FILE        = DATA_DIR / "sessoes.json"
QUANTIDADE_ALUNOS   = int(os.environ.get("QUANTIDADE_ALUNOS", "60"))
SENHA_INICIAL       = os.environ.get("SENHA_INICIAL", "trocar123")
SENHA_ADMIN         = os.environ.get("SENHA_ADMIN", "admin")
INATIVIDADE_MINUTOS = int(os.environ.get("INATIVIDADE_MINUTOS", "60"))
FLASK_SECRET        = os.environ.get("FLASK_SECRET") or secrets.token_hex(32)
ALUNOS_DIR          = Path(os.environ.get("ALUNOS_DIR", "/alunos"))

app = Flask(__name__)
app.secret_key = FLASK_SECRET
app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
ph = PasswordHasher()
_lock = threading.Lock()

# ── Persistência ────────────────────────────────────────────────────────────
def _load(path, default):
    with _lock:
        if not path.exists(): return default
        try: return json.loads(path.read_text(encoding="utf-8"))
        except: return default

def _save(path, data):
    with _lock:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(path)

carregar_alunos  = lambda: _load(ALUNOS_FILE, {})
salvar_alunos    = lambda d: _save(ALUNOS_FILE, d)
carregar_sessoes = lambda: _load(SESSOES_FILE, {})
salvar_sessoes   = lambda d: _save(SESSOES_FILE, d)

def inicializar_alunos():
    alunos = carregar_alunos(); mudou = False
    for i in range(1, QUANTIDADE_ALUNOS + 1):
        nome = f"aluno{i:02d}"
        if nome not in alunos:
            alunos[nome] = {"senha_hash": ph.hash(SENHA_INICIAL), "precisa_trocar": True,
                            "criado_em": datetime.now(timezone.utc).isoformat(), "ultimo_login": None}
            mudou = True
    if mudou: salvar_alunos(alunos)

# ── Docker ──────────────────────────────────────────────────────────────────
_dc: Optional[docker.DockerClient] = None
def dc():
    global _dc
    if _dc is None: _dc = docker.from_env()
    return _dc

gerar_token = lambda: "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(32))

def container_status(aluno):
    try: return dc().containers.get(f"sala_{aluno}").status
    except docker.errors.NotFound: return "nao_existe"

def container_rodando(aluno): return container_status(aluno) == "running"

def aguardar_code_server(aluno: str, timeout: int = 30) -> bool:
    """
    Aguarda o code-server do aluno estar realmente respondendo HTTP.
    Tenta a cada 1s por até `timeout` segundos.
    Retorna True se ficou pronto, False se expirou o tempo.
    """
    url = f"http://sala_{aluno}:8443/"
    inicio = time.time()
    while time.time() - inicio < timeout:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=2) as resp:
                # code-server responde 200 ou 302 quando está pronto
                if resp.status in (200, 302):
                    return True
        except Exception:
            pass
        time.sleep(1)
    app.logger.warning(f"Timeout aguardando code-server de sala_{aluno}")
    return False


def _apagar_config_yaml(aluno: str):
    p = ALUNOS_DIR / aluno / ".config" / "code-server" / "config.yaml"
    try:
        p.unlink(missing_ok=True)
    except Exception as e:
        app.logger.warning(f"Não foi possível remover config.yaml de {aluno}: {e}")

def _senha_config_yaml(aluno: str) -> str | None:
    """Lê a senha salva no config.yaml do aluno. Retorna None se não existir."""
    p = ALUNOS_DIR / aluno / ".config" / "code-server" / "config.yaml"
    try:
        for line in p.read_text().splitlines():
            if line.startswith("password:"):
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return None

def iniciar_container(aluno, token):
    cname = f"sala_{aluno}"
    try: container = dc().containers.get(cname)
    except docker.errors.NotFound:
        app.logger.error(f"{cname} não existe"); return False
    if container.status == "running":
        # code-server usa config.yaml se existir — comparar contra ele, não o env do Docker
        senha_efetiva = _senha_config_yaml(aluno)
        if senha_efetiva is None:
            # sem config.yaml: code-server usa o env PASSWORD; comparar contra ele
            env = container.attrs.get("Config", {}).get("Env") or []
            senha_efetiva = next((e.split("=", 1)[1] for e in env if e.startswith("PASSWORD=")), None)
        if senha_efetiva == token:
            return aguardar_code_server(aluno, timeout=15)
        # Senha efetiva não bate com o token — para para recriar
        try: container.stop(timeout=10)
        except Exception as e: app.logger.warning(f"Erro ao parar {cname}: {e}")
        try: container = dc().containers.get(cname)
        except docker.errors.NotFound:
            app.logger.error(f"{cname} sumiu após parar"); return False
    _apagar_config_yaml(aluno)
    try:
        attrs = container.attrs
        cfg = attrs["Config"]; hcfg = attrs["HostConfig"]
        env = [e for e in (cfg.get("Env") or []) if not e.startswith("PASSWORD=")]
        env.append(f"PASSWORD={token}")
        container.remove()
        api = dc().api
        new = api.create_container(
            image=cfg["Image"], name=cname, hostname=cfg.get("Hostname"), environment=env,
            host_config=api.create_host_config(
                binds=hcfg.get("Binds"), network_mode=hcfg.get("NetworkMode"),
                restart_policy={"Name": "no"}, mem_limit=hcfg.get("Memory") or 0,
                nano_cpus=hcfg.get("NanoCpus") or 0),
            networking_config=api.create_networking_config(
                {"sala_net": api.create_endpoint_config(aliases=[cname])}),
            labels=cfg.get("Labels") or {})
        api.start(new["Id"])
        # Aguarda o code-server estar realmente pronto antes de redirecionar
        return aguardar_code_server(aluno, timeout=45)
    except Exception as e:
        app.logger.exception(f"Falha ao iniciar {cname}: {e}"); return False

def parar_container(aluno):
    try:
        c = dc().containers.get(f"sala_{aluno}")
        if c.status == "running": c.stop(timeout=10)
    except docker.errors.NotFound: pass
    except Exception as e: app.logger.exception(f"Erro ao parar sala_{aluno}: {e}")

def listar_containers_ativos() -> set:
    """Retorna set com nomes dos containers sala_alunoXX que estão running."""
    try:
        containers = dc().containers.list(filters={"name": "sala_aluno", "status": "running"})
        return {c.name for c in containers}
    except:
        return set()

def stats_container(aluno):
    try:
        c = dc().containers.get(f"sala_{aluno}")
        if c.status != "running": return {}
        # timeout curto para não travar o painel
        import threading, queue
        q = queue.Queue()
        def _fetch():
            try: q.put(c.stats(stream=False))
            except: q.put(None)
        t = threading.Thread(target=_fetch, daemon=True)
        t.start()
        t.join(timeout=3)
        r = q.get_nowait() if not q.empty() else None
        if not r: return {}
        cd = r["cpu_stats"]["cpu_usage"]["total_usage"] - r["precpu_stats"]["cpu_usage"]["total_usage"]
        sd = r["cpu_stats"]["system_cpu_usage"] - r["precpu_stats"]["system_cpu_usage"]
        nc = r["cpu_stats"].get("online_cpus", 1)
        cpu = round((cd/sd)*nc*100, 1) if sd > 0 else 0
        ram = round(r["memory_stats"]["usage"]/1024/1024, 1)
        return {"cpu": cpu, "ram": ram}
    except: return {}

# ── Garbage collector ────────────────────────────────────────────────────────
def gc_loop():
    while True:
        try:
            time.sleep(60)
            sessoes = carregar_sessoes(); agora = time.time()
            timeout = INATIVIDADE_MINUTOS * 60
            exp = [a for a, s in sessoes.items() if agora - s.get("ultimo_acesso", 0) > timeout]
            for aluno in exp:
                parar_container(aluno); sessoes.pop(aluno, None)
                app.logger.info(f"GC: {aluno} desligado por inatividade")
            if exp: salvar_sessoes(sessoes)
        except: app.logger.exception("Erro no GC")

def iniciar_gc(): threading.Thread(target=gc_loop, daemon=True, name="gc").start()

# ── Rotas aluno ──────────────────────────────────────────────────────────────
@app.route("/")
def index():
    return redirect(url_for("conectar") if "aluno" in session else url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        u = (request.form.get("usuario") or "").strip().lower()
        s = request.form.get("senha") or ""
        alunos = carregar_alunos()
        if u not in alunos:
            flash("Usuário ou senha inválidos.", "erro"); return render_template("login.html")
        try: ph.verify(alunos[u]["senha_hash"], s)
        except VerifyMismatchError:
            flash("Usuário ou senha inválidos.", "erro"); return render_template("login.html")
        if ph.check_needs_rehash(alunos[u]["senha_hash"]):
            alunos[u]["senha_hash"] = ph.hash(s)
        alunos[u]["ultimo_login"] = datetime.now(timezone.utc).isoformat()
        salvar_alunos(alunos); session["aluno"] = u
        return redirect(url_for("trocar_senha") if alunos[u].get("precisa_trocar") else url_for("conectar"))
    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear(); return redirect(url_for("login"))

@app.route("/trocar-senha", methods=["GET", "POST"])
def trocar_senha():
    if "aluno" not in session: return redirect(url_for("login"))
    aluno = session["aluno"]; alunos = carregar_alunos()
    if request.method == "POST":
        atual = request.form.get("atual") or ""; nova = request.form.get("nova") or ""
        conf  = request.form.get("confirmacao") or ""
        try: ph.verify(alunos[aluno]["senha_hash"], atual)
        except VerifyMismatchError:
            flash("Senha atual incorreta.", "erro")
            return render_template("trocar_senha.html", obrigatorio=alunos[aluno].get("precisa_trocar"))
        if len(nova) < 6:
            flash("Mínimo 6 caracteres.", "erro")
            return render_template("trocar_senha.html", obrigatorio=alunos[aluno].get("precisa_trocar"))
        if nova != conf:
            flash("Confirmação não bate.", "erro")
            return render_template("trocar_senha.html", obrigatorio=alunos[aluno].get("precisa_trocar"))
        if nova == atual:
            flash("Nova senha deve ser diferente da atual.", "erro")
            return render_template("trocar_senha.html", obrigatorio=alunos[aluno].get("precisa_trocar"))
        alunos[aluno]["senha_hash"] = ph.hash(nova); alunos[aluno]["precisa_trocar"] = False
        salvar_alunos(alunos); flash("Senha alterada!", "sucesso")
        return redirect(url_for("conectar"))
    return render_template("trocar_senha.html", obrigatorio=alunos[aluno].get("precisa_trocar"))

@app.route("/conectar")
def conectar():
    if "aluno" not in session: return redirect(url_for("login"))
    aluno = session["aluno"]; alunos = carregar_alunos()
    if alunos.get(aluno, {}).get("precisa_trocar"): return redirect(url_for("trocar_senha"))
    sessoes = carregar_sessoes()
    if container_rodando(aluno) and aluno in sessoes:
        token = sessoes[aluno]["token"]
        sessoes[aluno]["ultimo_acesso"] = time.time()
        salvar_sessoes(sessoes)
        return render_template("conectar.html", aluno=aluno, url_destino=f"/code/{aluno}/",
                               token=token, aguardando=False)
    # Container não está rodando — gera token, salva sessão e inicia em background
    token = gerar_token()
    sessoes[aluno] = {"token": token, "ultimo_acesso": time.time(),
                      "iniciado_em": time.time()}
    salvar_sessoes(sessoes)
    def _iniciar_bg():
        if not iniciar_container(aluno, token):
            app.logger.error(f"Falha ao iniciar container de {aluno} em background")
    threading.Thread(target=_iniciar_bg, daemon=True).start()
    return render_template("conectar.html", aluno=aluno, url_destino=f"/code/{aluno}/",
                           token=token, aguardando=True)

@app.route("/aguardar")
def aguardar_env():
    if "aluno" not in session: return jsonify({"ok": False, "redirect": "/login"})
    aluno = session["aluno"]
    try:
        req = urllib.request.Request(f"http://sala_{aluno}:8443/")
        with urllib.request.urlopen(req, timeout=2) as resp:
            if resp.status in (200, 302):
                return jsonify({"ok": True})
    except Exception:
        pass
    return jsonify({"ok": False})

@app.route("/heartbeat", methods=["POST"])
def heartbeat():
    if "aluno" not in session: return {"ok": False}, 401
    aluno = session["aluno"]; sessoes = carregar_sessoes()
    if aluno in sessoes:
        sessoes[aluno]["ultimo_acesso"] = time.time(); salvar_sessoes(sessoes)
    return {"ok": True}

@app.route("/ping")
def ping():
    """JS do code-server chama a cada 30s. Se container caiu, devolve redirect."""
    if "aluno" not in session: return jsonify({"ok": False, "login": True})
    aluno = session["aluno"]
    if not container_rodando(aluno): return jsonify({"ok": False, "redirect": "/conectar"})
    sessoes = carregar_sessoes()
    if aluno in sessoes:
        sessoes[aluno]["ultimo_acesso"] = time.time(); salvar_sessoes(sessoes)
    return jsonify({"ok": True})

# ── Rotas admin ──────────────────────────────────────────────────────────────
def checar_admin():
    if not session.get("admin"): abort(403)

@app.route("/admin", methods=["GET", "POST"])
def admin_login():
    if session.get("admin"): return redirect(url_for("admin_painel"))
    if request.method == "POST":
        if request.form.get("senha") == SENHA_ADMIN:
            session["admin"] = True; return redirect(url_for("admin_painel"))
        flash("Senha incorreta.", "erro")
    return render_template("admin_login.html")

@app.route("/admin/sair")
def admin_logout():
    session.pop("admin", None); return redirect(url_for("admin_login"))

@app.route("/admin/painel")
def admin_painel():
    checar_admin()
    alunos = carregar_alunos(); sessoes = carregar_sessoes(); agora = time.time()
    # Uma única chamada Docker para listar todos os ativos
    ativos_set = listar_containers_ativos()
    lista = []
    for nome in sorted(alunos.keys()):
        ativo = f"sala_{nome}" in ativos_set
        # Stats só para containers ativos, e sem bloquear a renderização
        st = {}
        sess = sessoes.get(nome)
        lista.append({"nome": nome, "precisa_trocar": alunos[nome].get("precisa_trocar", False),
                      "ultimo_login": alunos[nome].get("ultimo_login"), "ativo_agora": ativo,
                      "minutos_inatividade": round((agora-sess["ultimo_acesso"])/60,1) if sess else None,
                      "cpu": st.get("cpu"), "ram": st.get("ram")})
    try:
        lines = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo") if ":" in l}
        ram_total = round(lines["MemTotal"]/1024/1024, 1)
        ram_livre = round(lines["MemAvailable"]/1024/1024, 1)
    except: ram_total = ram_livre = None
    return render_template("admin_painel.html", alunos=lista,
                           ativos=sum(1 for a in lista if a["ativo_agora"]),
                           ram_total=ram_total, ram_livre=ram_livre,
                           timeout_min=INATIVIDADE_MINUTOS)

@app.route("/admin/resetar/<aluno>", methods=["POST"])
def admin_resetar_senha(aluno):
    checar_admin(); alunos = carregar_alunos()
    if aluno not in alunos: abort(404)
    alunos[aluno]["senha_hash"] = ph.hash(SENHA_INICIAL); alunos[aluno]["precisa_trocar"] = True
    salvar_alunos(alunos); flash(f"Senha de {aluno} resetada.", "sucesso")
    return redirect(url_for("admin_painel"))

@app.route("/admin/parar/<aluno>", methods=["POST"])
def admin_parar_container(aluno):
    checar_admin(); parar_container(aluno)
    sessoes = carregar_sessoes(); sessoes.pop(aluno, None); salvar_sessoes(sessoes)
    flash(f"Container de {aluno} parado.", "sucesso"); return redirect(url_for("admin_painel"))

@app.route("/admin/reiniciar/<aluno>", methods=["POST"])
def admin_reiniciar_container(aluno):
    checar_admin(); sessoes = carregar_sessoes()
    token = sessoes.get(aluno, {}).get("token") or gerar_token()
    parar_container(aluno); time.sleep(2)
    if iniciar_container(aluno, token):
        sessoes[aluno] = {"token": token, "ultimo_acesso": time.time(), "iniciado_em": time.time()}
        salvar_sessoes(sessoes); flash(f"{aluno} reiniciado.", "sucesso")
    else: flash(f"Falha ao reiniciar {aluno}.", "erro")
    return redirect(url_for("admin_painel"))

@app.route("/admin/parar-todos", methods=["POST"])
def admin_parar_todos():
    checar_admin(); alunos = carregar_alunos(); sessoes = carregar_sessoes(); parados = 0
    for nome in alunos:
        if container_rodando(nome): parar_container(nome); sessoes.pop(nome, None); parados += 1
    salvar_sessoes(sessoes); flash(f"{parados} containers parados.", "sucesso")
    return redirect(url_for("admin_painel"))

@app.route("/admin/resetar-todas", methods=["POST"])
def admin_resetar_todas():
    checar_admin()
    if request.form.get("confirmacao") != "RESETAR TODAS":
        flash("Texto de confirmação incorreto.", "erro"); return redirect(url_for("admin_painel"))
    alunos = carregar_alunos()
    for nome in alunos:
        alunos[nome]["senha_hash"] = ph.hash(SENHA_INICIAL); alunos[nome]["precisa_trocar"] = True
    salvar_alunos(alunos); flash("Todas as senhas resetadas.", "sucesso")
    return redirect(url_for("admin_painel"))

@app.route("/admin/api/stats")
def admin_api_stats():
    checar_admin(); alunos = carregar_alunos(); sessoes = carregar_sessoes(); agora = time.time()
    ativos_set = listar_containers_ativos()
    result = {}
    for nome in alunos:
        ativo = f"sala_{nome}" in ativos_set
        st = stats_container(nome) if ativo else {}
        sess = sessoes.get(nome)
        result[nome] = {"ativo": ativo, "cpu": st.get("cpu"), "ram": st.get("ram"),
                        "inatividade": round((agora-sess["ultimo_acesso"])/60,1) if sess else None}
    return jsonify(result)

@app.route("/healthz")
def healthz(): return {"ok": True}

@app.context_processor
def injetar_versao():
    return {"versao_atual": versao_local().get("version", "")}

inicializar_alunos()
iniciar_gc()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)

# ---------------------------------------------------------------------------
# Navegador de arquivos dos alunos (professor)
# ---------------------------------------------------------------------------
import mimetypes


# Extensões que o visualizador abre como texto
TEXTO_EXTS = {
    ".py", ".txt", ".md", ".json", ".csv", ".js", ".ts", ".html",
    ".css", ".java", ".c", ".cpp", ".h", ".sh", ".yaml", ".yml",
    ".toml", ".ini", ".cfg", ".xml", ".sql", ".r", ".rb", ".go",
}

def listar_arvore(base: Path, rel: Path = Path(".")) -> list:
    """Retorna lista de dicts representando a árvore de arquivos."""
    resultado = []
    try:
        atual = base / rel
        entradas = sorted(atual.iterdir(), key=lambda e: (e.is_file(), e.name.lower()))
        for entrada in entradas:
            nome_rel = rel / entrada.name
            if entrada.name.startswith("."):
                continue  # oculta arquivos ocultos
            if entrada.is_dir():
                resultado.append({
                    "tipo": "dir",
                    "nome": entrada.name,
                    "caminho": str(nome_rel),
                    "filhos": listar_arvore(base, nome_rel),
                })
            else:
                resultado.append({
                    "tipo": "arquivo",
                    "nome": entrada.name,
                    "caminho": str(nome_rel),
                    "tamanho": entrada.stat().st_size,
                    "ext": entrada.suffix.lower(),
                })
    except PermissionError:
        pass
    return resultado


@app.route("/admin/arquivos/<aluno>")
def admin_arquivos(aluno):
    checar_admin()
    alunos = carregar_alunos()
    if aluno not in alunos:
        abort(404)
    workspace = ALUNOS_DIR / aluno / "workspace"
    if not workspace.exists():
        arvore = []
    else:
        arvore = listar_arvore(workspace)
    return render_template("admin_arquivos.html", aluno=aluno, arvore=arvore)


@app.route("/admin/arquivo/<aluno>/<path:caminho>")
def admin_ver_arquivo(aluno, caminho):
    checar_admin()
    alunos = carregar_alunos()
    if aluno not in alunos:
        abort(404)

    workspace = ALUNOS_DIR / aluno / "workspace"
    arquivo = (workspace / caminho).resolve()

    # Segurança: impede path traversal fora do workspace do aluno
    try:
        arquivo.relative_to(workspace.resolve())
    except ValueError:
        abort(403)

    if not arquivo.exists() or not arquivo.is_file():
        abort(404)

    ext = arquivo.suffix.lower()
    tamanho = arquivo.stat().st_size

    # Arquivos muito grandes: só avisa
    if tamanho > 500_000:
        return render_template("admin_arquivo.html",
                               aluno=aluno, caminho=caminho,
                               nome=arquivo.name, ext=ext,
                               conteudo=None,
                               erro="Arquivo muito grande para exibir (> 500 KB).")

    if ext in TEXTO_EXTS:
        try:
            conteudo = arquivo.read_text(encoding="utf-8", errors="replace")
        except Exception as e:
            conteudo = None
            erro = f"Não foi possível ler o arquivo: {e}"
        else:
            erro = None
        return render_template("admin_arquivo.html",
                               aluno=aluno, caminho=caminho,
                               nome=arquivo.name, ext=ext,
                               conteudo=conteudo, erro=erro)

    # Arquivo binário — só informa
    return render_template("admin_arquivo.html",
                           aluno=aluno, caminho=caminho,
                           nome=arquivo.name, ext=ext,
                           conteudo=None,
                           erro="Arquivo binário — não é possível visualizar como texto.")

# ---------------------------------------------------------------------------
# Versionamento e verificação de atualização
# ---------------------------------------------------------------------------
import urllib.request
import urllib.error

VERSION_FILE = Path("/app/version.json")
GITHUB_REPO  = "seu-usuario/sala-de-aula-docker"  # atualizar antes de publicar
_update_cache = {"result": None, "checado_em": 0}
_update_lock  = threading.Lock()

def versao_local() -> dict:
    try:
        return json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    except:
        return {"version": "desconhecida", "release_date": "", "changelog": {}}

def verificar_atualizacao(force=False) -> dict:
    """
    Verifica no GitHub se existe versão mais recente.
    Resultado é cacheado por 1 hora para não sobrecarregar a API.
    Retorna dict com: versao_local, versao_remota, tem_atualizacao, erro
    """
    with _update_lock:
        agora = time.time()
        # Cache de 1 hora
        if not force and _update_cache["result"] and agora - _update_cache["checado_em"] < 3600:
            return _update_cache["result"]

        local = versao_local()
        result = {
            "versao_local": local.get("version", "desconhecida"),
            "versao_remota": None,
            "tem_atualizacao": False,
            "url_release": f"https://github.com/{GITHUB_REPO}/releases/latest",
            "erro": None,
        }

        try:
            url = f"https://api.github.com/repos/{GITHUB_REPO}/releases/latest"
            req = urllib.request.Request(url, headers={"User-Agent": "sala-de-aula-docker"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode())
                tag = data.get("tag_name", "").lstrip("v")
                result["versao_remota"] = tag
                result["url_release"]   = data.get("html_url", result["url_release"])

                # Compara versões (ex: "1.2.0" > "1.0.0")
                def parse(v):
                    try: return tuple(int(x) for x in v.split("."))
                    except: return (0, 0, 0)

                if parse(tag) > parse(result["versao_local"]):
                    result["tem_atualizacao"] = True

        except urllib.error.URLError:
            result["erro"] = "sem_internet"
        except Exception as e:
            result["erro"] = str(e)

        _update_cache["result"]     = result
        _update_cache["checado_em"] = agora
        return result


@app.route("/admin/api/versao")
def admin_api_versao():
    """Chamado pelo painel admin via JS para verificar atualizações."""
    checar_admin()
    force = request.args.get("force") == "1"
    return jsonify(verificar_atualizacao(force=force))


@app.route("/admin/changelog")
def admin_changelog():
    checar_admin()
    info = versao_local()
    return render_template("admin_changelog.html", info=info)

@app.route("/changelog")
def changelog():
    info = versao_local()
    return render_template("changelog.html", info=info)

@app.route("/about")
def about():
    return render_template("about.html")
