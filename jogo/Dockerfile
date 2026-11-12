# Bonus game: browser port (pinned commit) + nginx. The game data is NOT in the
# image; it is mounted read-only from ./jogo-data (see preparar_jogo.sh).
FROM node:22-alpine AS build
ARG PORT_REF=5c6cccc56c1df5c3717c0b39953d5fe833f97b73
WORKDIR /app
ADD https://github.com/joncodeofficial/gta-vice-city-wasm/archive/${PORT_REF}.tar.gz /tmp/port.tar.gz
RUN tar -xzf /tmp/port.tar.gz --strip-components=1 && rm /tmp/port.tar.gz
COPY code-sphere.patch .
# The upstream page keeps the game in the browser (Service Worker + OPFS), which
# needs HTTPS. The patch makes it read the data the server already has.
RUN apk add --no-cache patch && patch -p1 < code-sphere.patch && rm public/sw.js
# Upstream re-downloads the whole package on every start; let nginx's ETag decide.
RUN grep -q "fetch(data_content, { cache: 'no-store' })" public/game.js \
    && sed -i "s/fetch(data_content, { cache: 'no-store' })/fetch(data_content, { cache: 'no-cache' })/" public/game.js
RUN corepack enable && pnpm install --frozen-lockfile && pnpm exec vite build --base=/jogo/

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html/jogo
COPY nginx.conf /etc/nginx/conf.d/default.conf
