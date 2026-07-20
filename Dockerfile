# Dockerfile para Akvorado
# Build multi-stage para otimizar tamanho da imagem

# Stage 1: Builder
FROM golang:alpine AS builder

# Instalar dependências de build
RUN apk add --no-cache git make gcc musl-dev nodejs npm curl zip

# Instalar pnpm globalmente
RUN npm install -g pnpm

# Clonar repositório do Akvorado (versão v2.0.4 - latest stable)
WORKDIR /build
RUN git clone --branch v2.0.4 --depth 1 https://github.com/akvorado/akvorado.git .

# Build do binário
RUN go mod download
RUN make

# Verificar onde o binário foi gerado
RUN find /build -name "akvorado" -o -name "akvorado-*" | head -10

# Stage 2: Runtime
FROM alpine:latest

# Instalar dependências runtime
RUN apk add --no-cache ca-certificates tzdata wget

# Criar diretórios
RUN mkdir -p /etc/akvorado /var/lib/geoip /var/log/akvorado

# Copiar binário do builder (pode estar em bin/ ou outro diretório)
COPY --from=builder /build/bin/akvorado /usr/local/bin/akvorado

# Tornar executável
RUN chmod +x /usr/local/bin/akvorado

# Usuário não-root
RUN addgroup -g 1000 akvorado && \
    adduser -D -u 1000 -G akvorado akvorado && \
    chown -R akvorado:akvorado /var/lib/geoip /var/log/akvorado

# Expor portas
EXPOSE 8080 8081 8082 2055/udp 6343/udp 4739/udp

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --spider -q http://localhost:8080/health || exit 1

# Usuário
USER akvorado

# Entrypoint
ENTRYPOINT ["/usr/local/bin/akvorado"]
CMD ["--help"]
