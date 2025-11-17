# Builder stage: build Anubis from source using Go on Alpine
FROM golang:1.24-alpine AS builder

# Install build tools, git, Node, bash, and other basics
RUN apk add --no-cache \
    git \
    ca-certificates \
    build-base \
    nodejs \
    npm \
    bash

# Install esbuild CLI globally so build.sh can call `esbuild`
RUN npm install -g esbuild

WORKDIR /app

# Go module files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source (Anubis repo root)
COPY . .

# Install JS dependencies for the Preact challenge
WORKDIR /app/lib/challenge/preact
# Prefer npm ci if package-lock.json exists, otherwise fall back to npm install
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# Back to repo root for subsequent steps
WORKDIR /app

# Build Preact (and other JS) assets so static/app.js exists
RUN ./lib/challenge/preact/build.sh

# Build the Anubis binary for Linux/amd64
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -o /anubis ./cmd/anubis


# Runtime image
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install ca-certificates (useful for HTTPS targets / metrics)
RUN apt-get update && apt-get install -y \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Create non-root user (let system pick UID to avoid clashes)
RUN useradd -m anubis

# Copy the compiled binary from the builder
COPY --from=builder /anubis /usr/local/bin/anubis

USER anubis

# Default Anubis bind port and envs
EXPOSE 8923
ENV BIND=":8923"

ENTRYPOINT ["/usr/local/bin/anubis"]
