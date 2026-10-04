FROM rust:slim-bookworm AS rust-builder
WORKDIR /app
RUN apt-get update && apt-get install -y pkg-config libssl-dev bubblewrap
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim AS flutter-builder
RUN apt-get update && apt-get install -y curl git unzip xz-utils zip libglu1-mesa gzip
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN flutter channel stable && flutter upgrade && flutter config --enable-web
WORKDIR /app
COPY . .
RUN flutter create --platforms=web .
RUN rm -f web/index.html
COPY loader.html web/index.html
COPY sitemap.xml web/sitemap.xml
COPY robots.txt web/robots.txt
COPY manifest.json web/manifest.json
COPY logo.png web/logo.png
RUN mkdir -p web/assets/assets
COPY pic.png web/assets/assets/logo.png
COPY editor.html web/editor.html
RUN flutter pub add web_socket_channel http speech_to_text flutter_markdown
RUN flutter pub get
RUN flutter build web --release --no-wasm-dry-run
RUN mkdir -p build/web/assets/assets && cp pic.png build/web/assets/assets/logo.png

RUN gzip -k -9 build/web/flutter_bootstrap.js || true
RUN gzip -k -9 build/web/main.dart.js || true
RUN gzip -k -9 build/web/manifest.json || true

FROM debian:bookworm-slim
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    ca-certificates curl wget unzip zip xz-utils git lsof jq nano bubblewrap gnupg \
    build-essential gcc g++ make cmake clang llvm pkg-config \
    sqlite3 libsqlite3-dev libpq-dev default-libmysqlclient-dev \
    mariadb-client postgresql-client libssl-dev openssl libffi-dev libsodium-dev \
    ffmpeg imagemagick libmagickwand-dev libvips-dev libjpeg62-turbo-dev libpng-dev libgif-dev libwebp-dev libsndfile1-dev \
    python3 python3-pip python3-venv python3-dev python-is-python3 libopenblas-dev libomp-dev \
    libxml2-dev libxslt1-dev php-cli \
    libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxrandr2 libgbm1 libasound2 libpango-1.0-0 \
    libpangocairo-1.0-0 libnspr4 libnss3 libpci3 libuuid1

RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg && \
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" > /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && apt-get install -y --no-install-recommends mongodb-database-tools

RUN curl -fsSL https://deb.nodesource.com/setup_current.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g serve pm2

RUN LATEST_GO=$(curl -s https://go.dev/VERSION?m=text | head -n 1) \
    && curl -L -o go.tar.gz "https://go.dev/dl/${LATEST_GO}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf go.tar.gz \
    && rm go.tar.gz

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

RUN rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/go/bin:/root/.cargo/bin:/app/data/global_cache/python/bin:${PATH}"

COPY --from=rust-builder /app/target/release/silent_hosting /app/silent_hosting
COPY --from=flutter-builder /app/build/web /app/public

EXPOSE 8080
ENV PORT=8080

RUN printf '#!/bin/sh\nulimit -u 65535 2>/dev/null || true\nulimit -n 65535 2>/dev/null || true\nexec ./silent_hosting\n' > /app/entrypoint.sh \
    && chmod +x /app/entrypoint.sh

CMD ["/app/entrypoint.sh"]
