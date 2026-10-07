// Player de áudio do monitor — injetado no vnc.html do noVNC.
//
// O VNC não transporta áudio. O som do container chega por um segundo canal:
// PulseAudio (sink virtual) -> module-simple-protocol-tcp -> websockify -> este script.
// O stream é PCM cru s16le, mono, 22050 Hz, sem codec, para manter a latência baixa.
//
// Cada pedaço vira um AudioBuffer agendado no relógio do AudioContext, colado no
// fim do anterior. NÃO usar AudioWorklet: o Chrome só o expõe em contexto seguro
// (HTTPS ou localhost), e os Chromebooks abrem a sala em http://IP-DO-SERVIDOR/ —
// lá audioWorklet é undefined e o som nunca tocava.
//
// Ver ADR-0011.

(function () {
  "use strict";

  var TAXA = 22050;
  var LATENCIA_ALVO = 0.15; // segundos acumulados antes de começar a tocar
  var LATENCIA_MAX = 0.50;  // acima disso descarta o atraso acumulado
  var BLOCO_MIN = 512;      // amostras (~23 ms) agrupadas por nó, para não criar nó demais

  var m = window.location.pathname.match(/\/screen\/([^\/]+)\//);
  if (!m) return;
  var aluno = m[1];

  var ctx = null, ws = null;
  var ligado = false, resto = null, tentarDeNovo = null;
  var proximo = 0, descartando = false;
  var pendente = [], pendenteN = 0;

  var botao = document.createElement("button");
  botao.textContent = "Ativar som";
  botao.setAttribute("tabindex", "-1");
  botao.setAttribute("title", "O som do seu programa só toca depois de um clique (regra do navegador)");
  botao.style.cssText = [
    "position:fixed", "right:12px", "bottom:12px", "z-index:99999",
    "padding:8px 14px", "border:0", "border-radius:6px",
    "font:600 13px system-ui,sans-serif", "color:#fff", "cursor:pointer",
    "background:linear-gradient(135deg,#2f4bd8,#7b2fd8)", "opacity:.85"
  ].join(";");
  botao.addEventListener("mouseenter", function () { botao.style.opacity = "1"; });
  botao.addEventListener("mouseleave", function () { botao.style.opacity = ".85"; });

  function estado(texto, ativo) {
    botao.textContent = texto;
    botao.style.background = ativo
      ? "linear-gradient(135deg,#1f9d55,#2f8fd8)"
      : "linear-gradient(135deg,#2f4bd8,#7b2fd8)";
  }

  // O noVNC só entrega teclado ao jogo se o foco estiver no canvas. Um botão com
  // foco engoliria as teclas do aluno, então devolvemos o foco assim que possível.
  function devolverFoco() {
    botao.blur();
    var alvo = document.querySelector("#noVNC_canvas") ||
               document.querySelector("canvas") ||
               document.body;
    if (alvo && alvo.focus) {
      try { alvo.focus({ preventScroll: true }); } catch (e) { alvo.focus(); }
    }
  }

  function converter(buffer) {
    var bytes = new Uint8Array(buffer);
    if (resto && resto.length) {
      var juntos = new Uint8Array(resto.length + bytes.length);
      juntos.set(resto); juntos.set(bytes, resto.length);
      bytes = juntos;
    }
    resto = null;
    var n = bytes.length >> 1;
    if (bytes.length & 1) resto = bytes.slice(n * 2);
    var f32 = new Float32Array(n);
    for (var i = 0; i < n; i++) {
      // s16le explícito: não dependemos do endianness da máquina do aluno.
      var v = (bytes[i * 2 + 1] << 8) | bytes[i * 2];
      if (v & 0x8000) v -= 0x10000;
      f32[i] = v / 32768;
    }
    return f32;
  }

  // Agenda as amostras logo depois do que já está na fila do AudioContext.
  // proximo é o instante (relógio do áudio) em que o último pedaço termina.
  function agendar(amostras) {
    var agora = ctx.currentTime;
    var adiantado = proximo - agora;
    if (adiantado < 0.01) {
      // Início ou underrun: acumula LATENCIA_ALVO de folga antes de tocar de novo.
      proximo = agora + LATENCIA_ALVO;
      descartando = false;
    } else if (descartando || adiantado > LATENCIA_MAX) {
      // Atraso acumulado (aba em segundo plano, rede engasgou): joga fora até
      // voltar à latência alvo. Preferimos perder som a tocar meio segundo atrasado.
      descartando = adiantado > LATENCIA_ALVO;
      if (descartando) return;
    }
    var buf = ctx.createBuffer(1, amostras.length, TAXA);
    buf.getChannelData(0).set(amostras);
    var src = ctx.createBufferSource();
    src.buffer = buf;
    src.connect(ctx.destination);
    src.start(proximo);
    proximo += buf.duration;
  }

  function receber(f32) {
    pendente.push(f32);
    pendenteN += f32.length;
    if (pendenteN < BLOCO_MIN) return;
    var bloco = pendente.length === 1 ? pendente[0] : new Float32Array(pendenteN);
    if (pendente.length > 1) {
      for (var i = 0, o = 0; i < pendente.length; i++) {
        bloco.set(pendente[i], o); o += pendente[i].length;
      }
    }
    pendente = []; pendenteN = 0;
    agendar(bloco);
  }

  function limparFila() {
    resto = null; pendente = []; pendenteN = 0;
    proximo = 0; descartando = false;
  }

  function conectar() {
    var proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    var url = proto + "//" + window.location.host + "/audio/" + aluno + "/";
    // O websockify negocia base64 quando o cliente não pede nada; exigimos binário.
    ws = new WebSocket(url, ["binary"]);
    ws.binaryType = "arraybuffer";

    ws.onopen = function () { estado("Som ligado", true); };
    ws.onmessage = function (ev) {
      if (!ctx || typeof ev.data === "string") return;
      var f32 = converter(ev.data);
      if (f32.length) receber(f32);
    };
    ws.onclose = function () {
      if (!ligado) return;
      estado("Som reconectando...", false);
      limparFila();
      tentarDeNovo = setTimeout(conectar, 2000);
    };
    ws.onerror = function () { try { ws.close(); } catch (e) {} };
  }

  function desligar() {
    ligado = false;
    if (tentarDeNovo) { clearTimeout(tentarDeNovo); tentarDeNovo = null; }
    if (ws) { try { ws.close(); } catch (e) {} ws = null; }
    if (ctx) { try { ctx.close(); } catch (e) {} ctx = null; }
    limparFila();
    estado("Ativar som", false);
  }

  // Tudo síncrono dentro do clique: o Chrome só libera o AudioContext quando ele
  // é criado (ou retomado) durante o gesto do usuário.
  function ligar() {
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) {
      estado("Som indisponível", false);
      botao.disabled = true;
      return;
    }
    estado("Conectando...", false);
    // Na taxa do stream o navegador não precisa reamostrar; se recusar a taxa,
    // o contexto padrão também serve — o AudioBuffer de 22050 Hz é convertido.
    try { ctx = new AC({ sampleRate: TAXA }); } catch (e) { ctx = new AC(); }
    if (ctx.state === "suspended" && ctx.resume) ctx.resume();
    limparFila();
    ligado = true;
    conectar();
  }

  botao.addEventListener("click", function (ev) {
    ev.preventDefault();
    ev.stopPropagation();
    if (ligado) {
      desligar();
    } else {
      try { ligar(); } catch (e) { desligar(); estado("Som falhou", false); }
    }
    devolverFoco();
  });

  // Impede que teclas digitadas com o botão sob o cursor virem "clique" nele.
  botao.addEventListener("keydown", function (ev) { ev.preventDefault(); devolverFoco(); });

  function instalar() { document.body.appendChild(botao); }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", instalar);
  } else {
    instalar();
  }
})();
