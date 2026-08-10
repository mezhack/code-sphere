FROM python:3.12-slim

WORKDIR /app

# Dependências do sistema (se precisar futuramente)
# Repositórios em HTTPS: redes com filtro de conteúdo bloqueiam o apt em HTTP (403 Forbidden)
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' \
        /etc/apt/sources.list.d/debian.sources \
    && apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

# Gunicorn: servidor WSGI de produção. 1 worker é suficiente para 60 alunos
# (a carga é leve — quase toda a computação é IO em Docker socket e arquivos).
# Múltiplos workers complicariam a thread do garbage collector.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", \
     "--threads", "4", "--timeout", "60", "app:app"]
