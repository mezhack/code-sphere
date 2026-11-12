"""Checagem do bônus: python test_eg.py (dentro da imagem do portal)."""
import os, tempfile
os.environ["DATA_DIR"] = tempfile.mkdtemp()
os.environ["QUANTIDADE_ALUNOS"] = "1"
import app

n = app.eg_normalizar
assert n("Herança") == n("heranca") == n(" HERANÇA ") == "heranca"
assert n("__init__") == n("init()") == "init"
assert n("Instância") == "instancia" and n("método") == "metodo"
assert n("!!!") == ""

assert app.eg_luz("a", {}) == "nunca"
assert app.eg_luz("a", {"a": [{"certa": True}, {"certa": False}]}) == "erro"
assert app.eg_luz("a", {"a": [{"certa": False}, {"certa": True}]}) == "ok"

app.container_status = lambda nome: "running"
app._save(app.EG_PERGUNTAS_FILE, [{"pergunta": "P?", "respostas": ["Herança"]}])
c = app.app.test_client()
assert c.get("/eg/pergunta").status_code == 404          # sem login
assert c.get("/eg/auth").status_code == 403
with c.session_transaction() as s: s["aluno"] = "aluno01"
assert c.get("/eg/auth").status_code == 403              # logado, sem passe
assert c.post("/eg/responder", json={"resposta": "x"}).status_code == 404  # sem pergunta sorteada
assert c.get("/eg/pergunta").get_json() == {"pergunta": "P?"}
assert c.post("/eg/responder", json={"resposta": "errado"}).get_json() == {"ok": False}
assert c.post("/eg/responder", json={"resposta": "heranca"}).status_code == 404  # tentativa única
assert c.get("/eg/auth").status_code == 403
c.get("/eg/pergunta")
assert c.post("/eg/responder", json={"resposta": "HERANCA"}).get_json() == {"ok": True}
assert c.get("/eg/auth").status_code == 200
assert c.post("/eg/ping").status_code == 204
assert [r["certa"] for r in app._load(app.EG_RESPOSTAS_FILE, {})["aluno01"]] == [False, True]
app._eg_passes["aluno01"] -= app.EG_PASSE_SEGUNDOS + 1    # aba fechada: passe vence
assert c.get("/eg/auth").status_code == 403 and c.post("/eg/ping").status_code == 403
app.container_status = lambda nome: "exited"              # bônus desligado
assert c.get("/eg/pergunta").status_code == 404
print("ok")
