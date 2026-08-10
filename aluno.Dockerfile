FROM lscr.io/linuxserver/code-server:latest

# Instala dependências como root antes de trocar para o usuário abc
USER root

# Dependências do sistema
# Repositórios em HTTPS: redes com filtro de conteúdo bloqueiam o apt em HTTP (403 Forbidden)
RUN sed -i 's|http://archive.ubuntu.com|https://archive.ubuntu.com|g; s|http://security.ubuntu.com|https://security.ubuntu.com|g; s|http://ports.ubuntu.com|https://ports.ubuntu.com|g' \
        /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Pygame (dependências de sistema — SDL2)
    python3-pygame \
    libsdl2-dev \
    libsdl2-image-dev \
    libsdl2-mixer-dev \
    libsdl2-ttf-dev \
    # PostgreSQL client (psql + biblioteca Python)
    postgresql-client \
    libpq-dev \
    # Display virtual (para pygame e outros programas gráficos)
    xvfb \
    x11vnc \
    novnc \
    python3-tk \
    # Áudio do monitor (sink virtual — o container não tem placa de som)
    pulseaudio \
    pulseaudio-utils \
    # Utilitários úteis
    git \
    curl \
    wget \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Permite que o usuário abc use sudo sem senha
RUN echo "abc ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/abc && \
    chmod 0440 /etc/sudoers.d/abc

# Cria link python → python3 (para quem digitar só "python")
RUN ln -sf /usr/bin/python3 /usr/bin/python

# Instala pacotes Python globais (acessíveis a todos os usuários)
RUN pip3 install --no-cache-dir --break-system-packages \
    pygame \
    pgzero \
    psycopg2-binary \
    requests \
    ipython

# Display virtual: script de inicialização (custom-cont-init.d é o único diretório
# que o linuxserver/code-server realmente executa na subida do container)
RUN mkdir -p /custom-cont-init.d && \
    printf '%s\n' \
    '#!/usr/bin/with-contenv bash' \
    'Xvfb :1 -screen 0 1280x720x24 -nolisten tcp &' \
    'sleep 2' \
    'x11vnc -display :1 -nopw -listen 127.0.0.1 -rfbport 5900 -forever -shared -bg' \
    'sleep 1' \
    'nohup websockify --web=/usr/share/novnc/ 6080 127.0.0.1:5900 >/tmp/novnc.log 2>&1 &' \
    '' \
    '# Áudio: o PulseAudio recusa rodar como root. Este script roda como abc nas' \
    '# imagens atuais do linuxserver, mas já rodou como root — trata os dois casos.' \
    '# auth-anonymous evita depender do cookie, que fica no HOME do daemon.' \
    'mkdir -p /tmp/pulse' \
    'COMO_ABC=""' \
    'if [ "$(id -u)" = "0" ]; then' \
    '  chown abc:abc /tmp/pulse' \
    '  COMO_ABC="s6-setuidgid abc"' \
    'fi' \
    '$COMO_ABC env HOME=/tmp/pulse PULSE_RUNTIME_PATH=/tmp/pulse pulseaudio -n \' \
    '  --load="module-null-sink sink_name=virtual" \' \
    '  --load="module-native-protocol-unix socket=/tmp/pulse/native auth-anonymous=1" \' \
    '  --load="module-simple-protocol-tcp source=virtual.monitor record=true listen=127.0.0.1 port=4713 format=s16le rate=22050 channels=1" \' \
    '  --exit-idle-time=-1 --disallow-exit --daemonize=yes >/tmp/pulse.log 2>&1' \
    'sleep 1' \
    'nohup websockify 6081 127.0.0.1:4713 >/tmp/audio.log 2>&1 &' \
    > /custom-cont-init.d/tela && chmod +x /custom-cont-init.d/tela

# Página inicial do noVNC redireciona para vnc.html com auto-connect e path correto
RUN printf '<script>\n\
var p = window.location.pathname.replace(/\\/+$/, "");\n\
window.location.replace("vnc.html?autoconnect=true&path=" + p.slice(1) + "/websockify");\n\
</script>\n' > /usr/share/novnc/index.html

# Player de áudio: injetado no vnc.html do próprio noVNC em vez de embrulhar a
# página num iframe, que quebraria o encaminhamento de teclado para o jogo.
COPY novnc-defaults/audio.js /usr/share/novnc/audio.js
RUN sed -i 's#</body>#<script src="audio.js"></script>\n</body>#' /usr/share/novnc/vnc.html && \
    grep -q 'audio.js' /usr/share/novnc/vnc.html

# DISPLAY aponta para o Xvfb
ENV DISPLAY=:1

# Sem gerenciador de janelas o SDL abre a janela em +590+310 e ela fica cortada
# na tela de 1280x720 — centralizar mantém o jogo inteiro visível no monitor
ENV SDL_VIDEO_CENTERED=1

# O som do jogo vai para o sink virtual do PulseAudio, de onde é transmitido ao
# navegador. A lista com dummy no fim é proposital: se o PulseAudio não subir,
# o SDL cai no driver mudo e o jogo continua rodando. Com "pulse" sozinho o
# sounds.play() levanta exceção e mata o jogo do aluno; deixar a variável vazia
# faria o SDL tentar o ALSA, que não existe aqui e também falha, com o terminal
# cheio de erro.
ENV SDL_AUDIODRIVER=pulse,dummy
ENV PULSE_SERVER=unix:/tmp/pulse/native

# Volta para o usuário padrão do linuxserver
USER abc
