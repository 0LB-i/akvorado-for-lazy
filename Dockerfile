# Dockerfile para Akvorado
# Build multi-stage para otimizar tamanho da imagem

# Stage 1: Builder
# ATENCAO: a versao do Go fica fixada de proposito. O akvorado v2.0.4 declara
# `go 1.25` e depende de golang.org/x/tools v0.38.0, que so entende o formato
# de export data ate o Go 1.25. Usar a tag flutuante `golang:alpine` (hoje Go
# 1.27) quebra o `go tool enumer` no meio do `make` com:
#   enumer: internal error: package "fmt" without types was imported from
#   "command-line-arguments"
# So suba esta versao junto com um upgrade do akvorado que tambem suba o x/tools.
FROM golang:1.25-alpine AS builder

# Instalar dependências de build
RUN apk add --no-cache git make gcc musl-dev nodejs npm curl zip

# Clonar repositório do Akvorado (versão v2.0.4 - latest stable)
WORKDIR /build
RUN git clone --branch v2.0.4 --depth 1 https://github.com/akvorado/akvorado.git .

# Instalar a versão exata do pnpm fixada em console/frontend/package.json
# (necessário: pnpm mais recente que o usado para gerar o pnpm-lock.yaml falha
# a verificação do binário nativo @pnpm/exe.* no `pnpm install --frozen-lockfile`)
RUN PNPM_VERSION=$(node -p "require('./console/frontend/package.json').packageManager.split('@')[1]") \
    && npm install -g pnpm@${PNPM_VERSION}

# Corrige a regressão do upstream que faz o orchestrator devolver HTTP 500
# "seeker can't seek" ao servir os CSVs dos dicionários do ClickHouse
# (asns.csv, protocols.csv, tcp.csv, udp.csv, icmp.csv). Ver o cabeçalho de
# patches/embed-seekable-fs.go para o diagnóstico completo.
COPY patches/embed-seekable-fs.go /build/common/embed/fs.go

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

# Healthcheck padrão da imagem (o docker-compose.yml sobrescreve por serviço).
# Não use `wget --spider`: ele faz HEAD, e as rotas do akvorado são registradas
# apenas como GET no gin, então HEAD cai em 404 e o wget sai com código 8.
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/api/v0/healthcheck || exit 1

# Usuário
USER akvorado

# Entrypoint
ENTRYPOINT ["/usr/local/bin/akvorado"]
CMD ["--help"]
