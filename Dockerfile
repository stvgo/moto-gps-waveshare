# Multi-stage build for root repo on Railway
FROM rust:slim-bookworm AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
COPY backend-rs/Cargo.toml backend-rs/Cargo.lock ./
COPY backend-rs/src ./src
RUN cargo build --release

FROM debian:bookworm-slim
WORKDIR /app
RUN apt-get update && apt-get install -y ca-certificates libssl3 curl && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/moto-gps-backend /app/moto-gps-backend
COPY backend-rs/app-debug.apk /app/app-debug.apk
ENV PORT=8787
EXPOSE 8787
CMD ["/app/moto-gps-backend"]
