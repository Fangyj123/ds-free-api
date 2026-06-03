ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

# Stage 1: Build frontend
FROM oven/bun:1 AS frontend
ARG HTTP_PROXY
ARG HTTPS_PROXY
ENV HTTP_PROXY=${HTTP_PROXY} HTTPS_PROXY=${HTTPS_PROXY}
WORKDIR /app/web
COPY web/package.json web/bun.lock* ./
RUN bun install --frozen-lockfile || bun install
COPY web/ .
RUN bun run build

# Stage 2: Build Rust backend
FROM rust:1.87-bookworm AS builder
ARG HTTP_PROXY
ARG HTTPS_PROXY
ENV HTTP_PROXY=${HTTP_PROXY} HTTPS_PROXY=${HTTPS_PROXY} \
    CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_HTTP_CHECK_REVOKE=false \
    GIT_SSL_NO_VERIFY=1
RUN git config --global http.sslVerify false && \
    sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
    HTTP_PROXY= HTTPS_PROXY= apt-get update && \
    HTTP_PROXY= HTTPS_PROXY= apt-get install -y --no-install-recommends cmake clang libclang-dev && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Cargo.toml Cargo.lock ./
# Cache dependencies
RUN mkdir src && echo "fn main(){}" > src/main.rs && cargo build --release && rm -rf src
COPY src/ src/
# Embed frontend dist
COPY --from=frontend /app/web/dist/ web/dist/
RUN touch src/main.rs && cargo build --release

# Stage 3: Runtime
FROM alpine:3.21
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=builder /app/target/release/ds-free-api /app/ds-free-api
COPY docker/config.example.toml /app/config/config.toml

ENV RUST_LOG=info \
    DS_DATA_DIR=/app/data \
    DS_CONFIG_PATH=/app/config/config.toml

EXPOSE 22217
ENTRYPOINT ["/app/ds-free-api"]
