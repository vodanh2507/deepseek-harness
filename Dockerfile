# syntax=docker/dockerfile:1

FROM node:24-bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_ENV=production

WORKDIR /app

# Native build dependencies required by DeepSeek Harness.
# The current repo builds Linux native components including
# landlock-run and flock.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        musl-tools \
        python3 \
        ca-certificates \
        nginx \
    && rm -rf /var/lib/apt/lists/*

# Do NOT use DockHosting's Corepack 0.24.1.
# DeepSeek Harness currently pins pnpm 11.7.0.
RUN npm install -g pnpm@11.7.0 \
    && pnpm --version

# Copy the complete monorepo.
COPY . .

# Install exactly according to the repository lockfile.
RUN pnpm install --frozen-lockfile

# Official DeepSeek Harness build.
RUN pnpm run build

# ---------------------------------------------------------
# Nginx reverse proxy
# ---------------------------------------------------------

RUN rm -f /etc/nginx/sites-enabled/default \
    && printf '%s\n' \
'server {' \
'    listen 8080;' \
'    listen [::]:8080;' \
'    server_name _;' \
'' \
'    client_max_body_size 512M;' \
'' \
'    location / {' \
'        proxy_pass http://127.0.0.1:3080;' \
'        proxy_http_version 1.1;' \
'' \
'        proxy_set_header Host 127.0.0.1:3080;' \
'        proxy_set_header Origin http://127.0.0.1:3080;' \
'        proxy_set_header X-Real-IP $remote_addr;' \
'        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
'        proxy_set_header X-Forwarded-Proto $scheme;' \
'' \
'        proxy_set_header Upgrade $http_upgrade;' \
'        proxy_set_header Connection "upgrade";' \
'' \
'        proxy_read_timeout 3600s;' \
'        proxy_send_timeout 3600s;' \
'    }' \
'}' \
> /etc/nginx/sites-enabled/deepseek-harness

# Start script
RUN printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'' \
'echo "Starting DeepSeek Harness..."' \
'echo "Node: $(node --version)"' \
'echo "pnpm: $(pnpm --version)"' \
'' \
'# DSH deliberately listens on loopback.' \
'# Nginx exposes it on the DockHosting application port.' \
'pnpm dsh web --port 3080 > /tmp/dsh.log 2>&1 &' \
'DSH_PID=$!' \
'' \
'sleep 3' \
'' \
'if ! kill -0 "$DSH_PID" 2>/dev/null; then' \
'    echo "DeepSeek Harness failed to start."' \
'    cat /tmp/dsh.log' \
'    exit 1' \
'fi' \
'' \
'echo "DeepSeek Harness started on 127.0.0.1:3080"' \
'' \
'nginx -t' \
'exec nginx -g "daemon off;"' \
> /usr/local/bin/start-dsh.sh \
    && chmod +x /usr/local/bin/start-dsh.sh

EXPOSE 8080

CMD ["/usr/local/bin/start-dsh.sh"]
