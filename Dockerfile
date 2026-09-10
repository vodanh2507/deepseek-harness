FROM node:24-bookworm

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       musl-tools \
       python3 \
       ca-certificates \
       nginx \
       git \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm@11.7.0

COPY . .

RUN pnpm install --no-frozen-lockfile

RUN git init \
    && git config user.email "build@localhost" \
    && git config user.name "Docker Build" \
    && git add -A \
    && git commit -m "Docker build"

# BẮT BUỘC PHẢI BUILD TRƯỚC ĐỂ SINH RA CÁC FILE CLI/LIB TRONG MONOREPO
RUN pnpm build

RUN rm -f /etc/nginx/sites-enabled/default

# Cấu hình Nginx lắng nghe cổng 8080 (hoặc cổng $PORT của Dockhosting) và trỏ về app chạy ở cổng nội bộ 3080
RUN printf '%s\n' \
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
'        proxy_set_header Host $host;' \
'        proxy_set_header X-Real-IP $remote_addr;' \
'        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
'        proxy_set_header X-Forwarded-Proto $scheme;' \
'        proxy_set_header Upgrade $http_upgrade;' \
'        proxy_set_header Connection "upgrade";' \
'        proxy_read_timeout 3600s;' \
'        proxy_send_timeout 3600s;' \
'    end' \
'}' \
> /etc/nginx/sites-enabled/deepseek-harness

# Sửa lại start.sh để lắng nghe chính xác trên cổng nội bộ 3080 và bắt buộc bind ra 0.0.0.0 nếu CLI hỗ trợ
RUN printf '%s\n' \
'#!/bin/sh' \
'set -e' \
'' \
'# Khởi chạy ứng dụng ở cổng 3080 để khớp với proxy_pass của Nginx' \
'pnpm dsh web --port 3080 > /tmp/dsh.log 2>&1 &' \
'DSH_PID=$!' \
'' \
'sleep 5' \
'' \
'if ! kill -0 "$DSH_PID" 2>/dev/null; then' \
'    cat /tmp/dsh.log' \
'    exit 1' \
'fi' \
'' \
'nginx -t' \
'exec nginx -g "daemon off;"' \
> /usr/local/bin/start.sh \
&& chmod +x /usr/local/bin/start.sh

EXPOSE 8080

CMD ["/usr/local/bin/start.sh"]
