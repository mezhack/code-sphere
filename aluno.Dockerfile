FROM lscr.io/linuxserver/code-server:latest

# Instala dependências como root antes de trocar para o usuário abc
USER root

# Dependências do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    psycopg2-binary \
    requests \
    ipython

# Volta para o usuário padrão do linuxserver
USER abc
