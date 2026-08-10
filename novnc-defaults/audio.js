// Player de áudio do monitor — injetado no vnc.html do noVNC.
//
// O VNC não transporta áudio. O som do container chega por um segundo canal:
// PulseAudio (sink virtual) -> module-simple-protocol-tcp -> websockify -> este script.
// O stream é PCM cru s16le, mono, 22050 Hz, sem codec, para manter a latência baixa.
//
// Ver ADR-0011.

(function () {
  "use strict";

  var TAXA = 22050;
  var LATENCIA_ALVO = 0.15; // segundos acumulados antes de começar a tocar
  var LATENCIA_MAX = 0.50;  // acima disso descarta o atraso acumulado

  var m = window.location.pathname.match(/\/screen\/([^\/]+)\//);
  if (!m) return;
  var aluno = m[1];

  var ctx = null, node = null, ws = null;
  var ligado = false, resto = null, tentarDeNovo = null;

  var PROCESSOR = [
    "class PCMPlayer extends AudioWorkletProcessor {",
    "  constructor(options) {",
    "    super();",
    "    var o = options.processorOptions || {};",
    "    this.minAmostras = o.min || 0;",
    "    this.maxAmostras = o.max || 0;",
    "    this.fila = []; this.total = 0; this.offset = 0; this.tocando = false;",
    "    this.port.onmessage = (e) => {",
    "      if (e.data === 'limpar') {",
    "        this.fila = []; this.total = 0; this.offset = 0; this.tocando = false; return;",
    "      }",
    "      this.fila.push(e.data);",
    "      this.total += e.data.length;",
    // Se o buffer cresceu demais (aba em segundo plano, rede engasgou), descarta o
    // mais antigo. Preferimos perder som a acumular atraso indefinidamente.
    "      while (this.total > this.maxAmostras && this.fila.length > 1) {",
    "        var c = this.fila.shift();",
    "        this.total -= (c.length - this.offset);",
    "        this.offset = 0;",
    "      }",
    "    };",
    "  }",
    "  process(inputs, outputs) {",
    "    var saida = outputs[0][0];",
    "    if (!saida) return true;",
    "    if (!this.tocando) {",
    "      if (this.total < this.minAmostras) { saida.fill(0); return true; }",
    "      this.tocando = true;",
    "    }",
    "    var i = 0;",
    "    while (i < saida.length) {",
    "      if (this.fila.length === 0) {",
    // Underrun: completa com silêncio e volta a encher o buffer antes de seguir.
    "        saida.fill(0, i); this.tocando = false; break;",
    "      }",
    "      var c = this.fila[0];",
    "      var n = Math.min(saida.length - i, c.length - this.offset);",
    "      saida.set(c.subarray(this.offset, this.offset + n), i);",
    "      i += n; this.offset += n; this.total -= n;",
    "      if (this.offset >= c.length) { this.fila.shift(); this.offset = 0; }",
    "    }",
    "    return true;",
    "  }",
    "}",
    "registerProcessor('pcm-player', PCMPlayer);"
  ].join("\n");

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

  function conectar() {
    var proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    var url = proto + "//" + window.location.host + "/audio/" + aluno + "/";
    // O websockify negocia base64 quando o cliente não pede nada; exigimos binário.
    ws = new WebSocket(url, ["binary"]);
    ws.binaryType = "arraybuffer";

    ws.onopen = function () { estado("Som ligado", true); };
    ws.onmessage = function (ev) {
      if (!node || typeof ev.data === "string") return;
      var f32 = converter(ev.data);
      if (f32.length) node.port.postMessage(f32, [f32.buffer]);
    };
    ws.onclose = function () {
      if (!ligado) return;
      estado("Som reconectando...", false);
      if (node) node.port.postMessage("limpar");
      resto = null;
      tentarDeNovo = setTimeout(conectar, 2000);
    };
    ws.onerror = function () { try { ws.close(); } catch (e) {} };
  }

  function desligar() {
    ligado = false;
    if (tentarDeNovo) { clearTimeout(tentarDeNovo); tentarDeNovo = null; }
    if (ws) { try { ws.close(); } catch (e) {} ws = null; }
    if (node) { try { node.disconnect(); } catch (e) {} node = null; }
    if (ctx) { try { ctx.close(); } catch (e) {} ctx = null; }
    resto = null;
    estado("Ativar som", false);
  }

  async function ligar() {
    estado("Conectando...", false);
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC || !AC.prototype.audioWorklet) {
      estado("Som indisponível", false);
      botao.disabled = true;
      return;
    }
    // Abrimos o contexto na taxa do stream para não precisar reamostrar no navegador.
    ctx = new AC({ sampleRate: TAXA });
    var blob = new Blob([PROCESSOR], { type: "application/javascript" });
    var urlBlob = URL.createObjectURL(blob);
    try {
      await ctx.audioWorklet.addModule(urlBlob);
    } finally {
      URL.revokeObjectURL(urlBlob);
    }
    node = new AudioWorkletNode(ctx, "pcm-player", {
      numberOfInputs: 0,
      outputChannelCount: [1],
      processorOptions: {
        min: Math.round(TAXA * LATENCIA_ALVO),
        max: Math.round(TAXA * LATENCIA_MAX)
      }
    });
    node.connect(ctx.destination);
    if (ctx.state === "suspended") await ctx.resume();
    ligado = true;
    conectar();
  }

  botao.addEventListener("click", function (ev) {
    ev.preventDefault();
    ev.stopPropagation();
    if (ligado) {
      desligar();
    } else {
      ligar().catch(function () { desligar(); estado("Som falhou", false); });
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
