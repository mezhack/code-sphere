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
    # Display virtual (para matplotlib, pygame e outros programas gráficos)
    xvfb \
    x11vnc \
    novnc \
    python3-tk \
    python3-pil.imagetk \
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
    matplotlib \
    psycopg2-binary \
    requests \
    ipython

# Display virtual: script de inicialização (custom-cont-init.d é o único diretório
# que o linuxserver/code-server realmente executa na subida do container)
RUN mkdir -p /custom-cont-init.d && \
    printf '#!/usr/bin/with-contenv bash\n\
Xvfb :1 -screen 0 1280x720x24 -nolisten tcp &\n\
sleep 2\n\
x11vnc -display :1 -nopw -listen 127.0.0.1 -rfbport 5900 -forever -shared -bg\n\
sleep 1\n\
nohup websockify --web=/usr/share/novnc/ 6080 127.0.0.1:5900 >/tmp/novnc.log 2>&1 &\n' \
    > /custom-cont-init.d/tela && chmod +x /custom-cont-init.d/tela

# Força backend TkAgg via arquivo de configuração do matplotlib (independe de env vars)
RUN mkdir -p /home/abc/.config/matplotlib && \
    echo "backend: TkAgg" > /home/abc/.config/matplotlib/matplotlibrc

# Página inicial do noVNC redireciona para vnc.html com auto-connect e path correto
RUN printf '<script>\n\
var p = window.location.pathname.replace(/\\/+$/, "");\n\
window.location.replace("vnc.html?autoconnect=true&path=" + p.slice(1) + "/websockify");\n\
</script>\n' > /usr/share/novnc/index.html

# DISPLAY aponta para o Xvfb
ENV DISPLAY=:1
ENV MPLBACKEND=TkAgg

# Volta para o usuário padrão do linuxserver
USER abc
