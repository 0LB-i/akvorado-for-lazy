#!/bin/bash

# Script de Instalação do Akvorado
# Autor: Automação Akvorado
# Descrição: Instala e configura o Akvorado com Docker Compose

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usar docker-compose ou docker compose dependendo da versão
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Lê uma variável do .env (ou do .env.example, se o .env ainda não existir),
# com valor default
env_get() {
    local file=.env value
    [ -f "$file" ] || file=.env.example
    value=$(grep -E "^$1=" "$file" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d ' "')
    echo "${value:-$2}"
}

# Verificar se está rodando como root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Executando como root. Certifique-se de que o Docker está instalado."
    fi
}

# Verificar dependências
check_dependencies() {
    log_info "Verificando dependências..."

    local missing_deps=0

    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker não está instalado"
        missing_deps=1
    else
        log_info "Docker encontrado: $(docker --version)"
    fi

    # Verificar Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose não está instalado"
        missing_deps=1
    else
        log_info "Docker Compose encontrado: $($DOCKER_COMPOSE version)"
    fi

    # Verificar Git
    if ! command -v git &> /dev/null; then
        log_warn "Git não está instalado (opcional)"
    fi

    # Verificar curl
    if ! command -v curl &> /dev/null; then
        log_warn "curl não está instalado (usado nas verificações de saúde)"
    fi

    if [ $missing_deps -eq 1 ]; then
        log_error "Instale as dependências faltantes e execute novamente"
        log_info "Para instalar Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
}

# Verificar portas disponíveis (respeitando portas personalizadas no .env)
check_ports() {
    # Numa reinstalação/atualização as portas estão ocupadas pela própria
    # stack: não faz sentido avisar.
    if [ -n "$(docker ps -q --filter 'name=^akvorado-' 2>/dev/null)" ]; then
        log_info "Stack Akvorado já está rodando, pulando verificação de portas."
        return
    fi

    log_info "Verificando portas disponíveis..."

    local tcp_ports=(
        "$(env_get CONSOLE_HTTP_PORT 8000)"
        "$(env_get ORCHESTRATOR_HTTP_PORT 8080)"
        "$(env_get ORCHESTRATOR_GRPC_PORT 8081)"
        8082  # API do inlet (network_mode: host, config/akvorado-inlet.yaml)
        "$(env_get CLICKHOUSE_HTTP_PORT 8123)"
        "$(env_get CLICKHOUSE_NATIVE_PORT 9000)"
        "$(env_get KAFKA_PORT 9092)"
        "$(env_get KAFKA_EXTERNAL_PORT 9093)"
    )
    local udp_ports=(2055 6343 4739)
    local port_in_use=0 port

    for port in "${tcp_ports[@]}"; do
        if ss -tln 2>/dev/null | grep -q ":$port " || netstat -tln 2>/dev/null | grep -q ":$port "; then
            log_warn "Porta TCP $port já está em uso"
            port_in_use=1
        fi
    done
    for port in "${udp_ports[@]}"; do
        if ss -uln 2>/dev/null | grep -q ":$port " || netstat -uln 2>/dev/null | grep -q ":$port "; then
            log_warn "Porta UDP $port já está em uso"
            port_in_use=1
        fi
    done

    if [ $port_in_use -eq 1 ]; then
        log_warn "Algumas portas estão em uso. Edite o arquivo .env para usar portas diferentes."
        read -r -p "Deseja continuar mesmo assim? (s/N) " -n 1
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
}

# Instalações antigas rodavam o Kafka em modo Zookeeper (confluentinc/cp-kafka).
# O Kafka atual roda em modo KRaft e não consegue abrir esse diretório de dados
# (o meta.properties antigo não tem node.id). Os dados no Kafka são só um
# buffer entre inlet e outlet, então basta mover para um backup e começar
# vazio: só se perdem flows ainda não consumidos pelo outlet.
migrate_kafka_zookeeper_data() {
    local meta="data/kafka/meta.properties"
    [ -f "$meta" ] || return 0

    if [ ! -r "$meta" ]; then
        log_warn "Sem permissão para ler $meta; não foi possível verificar se é do Kafka antigo (Zookeeper)."
        return 0
    fi
    grep -q '^node\.id=' "$meta" && return 0

    local backup
    backup="data/kafka.zookeeper-backup-$(date +%Y%m%d_%H%M%S)"
    log_warn "data/kafka contém dados do Kafka antigo (modo Zookeeper), incompatíveis com o modo KRaft."
    log_warn "Movendo para $backup (pode apagar depois que a stack estiver ok)."

    # Garante que o container antigo não está usando o diretório
    $DOCKER_COMPOSE stop kafka > /dev/null 2>&1 || true

    if ! mv data/kafka "$backup"; then
        log_error "Não foi possível mover data/kafka. Execute novamente com sudo."
        exit 1
    fi
    mkdir -p data/kafka
}

# Configurar ambiente
setup_environment() {
    log_info "Configurando ambiente..."

    # Verificar se .env existe
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            log_info "Criando arquivo .env a partir do .env.example"
            cp .env.example .env
        else
            log_error "Arquivo .env não encontrado"
            exit 1
        fi
    fi

    migrate_kafka_zookeeper_data

    # Criar diretórios necessários
    log_info "Criando diretórios..."
    mkdir -p data/{clickhouse,kafka,geoip,console}
    mkdir -p logs
    mkdir -p config

    # Gerar config/akvorado-orchestrator.yaml a partir do template,
    # aplicando as credenciais definidas no .env (só na primeira vez)
    if [ ! -f config/akvorado-orchestrator.yaml ]; then
        if [ -f config/akvorado-orchestrator.yaml.example ]; then
            log_info "Gerando config/akvorado-orchestrator.yaml a partir do template..."
            local db_user db_password
            db_user=$(grep -E '^CLICKHOUSE_USER=' .env | cut -d'=' -f2-)
            db_password=$(grep -E '^CLICKHOUSE_PASSWORD=' .env | cut -d'=' -f2-)
            db_user=${db_user:-akvorado}
            db_password=${db_password:-akvorado123}

            # Escapa \, & e o delimitador | para uso seguro no lado direito do sed
            db_user=$(printf '%s' "$db_user" | sed -e 's/[\&|]/\\&/g')
            db_password=$(printf '%s' "$db_password" | sed -e 's/[\&|]/\\&/g')

            sed \
                -e "s|__AKVORADO_DB_USER__|${db_user}|g" \
                -e "s|__AKVORADO_DB_PASSWORD__|${db_password}|g" \
                config/akvorado-orchestrator.yaml.example > config/akvorado-orchestrator.yaml
        else
            log_error "Template config/akvorado-orchestrator.yaml.example não encontrado"
            exit 1
        fi
    fi

    # Ajustar permissões
    log_info "Ajustando permissões..."
    chmod -R 755 data
    chmod -R 755 logs

    # Kafka (appuser da imagem apache/kafka) e o Console (usuário "akvorado"
    # do Dockerfile) rodam como uid:gid 1000:1000 dentro do container, então
    # precisam ser donos dos diretórios de dados no host para escrever neles.
    log_info "Configurando permissões do Kafka..."
    chown -R 1000:1000 data/kafka 2>/dev/null || log_warn "Não foi possível ajustar permissões do Kafka (pode precisar de root)"

    log_info "Configurando permissões do Console..."
    chown -R 1000:1000 data/console 2>/dev/null || log_warn "Não foi possível ajustar permissões do Console (pode precisar de root)"
}

# Detectar suporte a AVX2 da CPU e fixar a versão do ClickHouse
# CPUs sem AVX2 (ex: Xeon anteriores a Haswell/v3, como X5670, E7-4870,
# E5-2697 v2) travam com "Illegal instruction" em builds do ClickHouse
# >= 23.5, que passaram a exigir AVX2. Nesse caso, fixa uma versão LTS
# anterior a essa exigência.
detect_clickhouse_version() {
    if grep -q '^CLICKHOUSE_VERSION=' .env 2>/dev/null; then
        log_info "CLICKHOUSE_VERSION já definido em .env, mantendo o valor atual."
        return
    fi

    if grep -qm1 avx2 /proc/cpuinfo 2>/dev/null; then
        log_info "CPU com suporte a AVX2 detectado, usando ClickHouse mais recente."
    else
        log_warn "CPU sem suporte a AVX2 detectado."
        log_warn "Fixando ClickHouse em 23.3 (LTS) para evitar 'Illegal instruction'."
        echo "CLICKHOUSE_VERSION=23.3" >> .env
    fi
}

# Verificar bancos de dados GeoIP
download_geoip() {
    log_info "Configurando bancos de dados GeoIP..."

    if [ ! -f data/geoip/GeoLite2-ASN.mmdb ] || [ ! -f data/geoip/GeoLite2-Country.mmdb ]; then
        log_warn "Bancos de dados GeoIP não encontrados"
        log_info "Para usar GeoIP, você precisa:"
        log_info "1. Criar uma conta gratuita em: https://www.maxmind.com/en/geolite2/signup"
        log_info "2. Baixar os arquivos GeoLite2-ASN.mmdb, GeoLite2-Country.mmdb e GeoLite2-City.mmdb"
        log_info "3. Colocar os arquivos em: data/geoip/"
        log_warn "O Akvorado funcionará sem GeoIP, mas sem informações de país/ASN"
    else
        log_info "Bancos de dados GeoIP encontrados"
    fi
}

# Versões anteriores deste script geravam config/clickhouse/users.xml com um
# perfil "default" e quotas. Esse arquivo era montado em config.d/ (config do
# servidor), onde blocos <profiles>/<quotas> não pertencem, e de qualquer forma
# só repetia os defaults do ClickHouse (exceto um teto de 10 GB por query).
# Remove o arquivo legado se for exatamente o que geramos.
cleanup_legacy_configs() {
    local legacy=config/clickhouse/users.xml
    if [ -f "$legacy" ] && grep -q '<max_memory_usage>10000000000</max_memory_usage>' "$legacy" \
        && grep -q '<load_balancing>random</load_balancing>' "$legacy"; then
        log_info "Removendo $legacy legado (gerado por versões antigas deste script)..."
        rm -f "$legacy"
    fi
}

# Conta quantos serviços estão healthy (ou rodando, para os sem healthcheck)
count_ready_services() {
    local svc cid state ready=0
    while read -r svc; do
        cid=$($DOCKER_COMPOSE ps -q "$svc" 2>/dev/null)
        [ -n "$cid" ] || continue
        state=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null)
        if [ "$state" = "healthy" ] || [ "$state" = "running" ]; then
            ready=$((ready + 1))
        fi
    done < <($DOCKER_COMPOSE config --services)
    echo "$ready"
}

# Iniciar serviços
start_services() {
    log_info "Iniciando serviços do Akvorado..."

    # Build e pull das imagens
    log_info "Construindo imagem do Akvorado (isso pode levar alguns minutos)..."
    $DOCKER_COMPOSE build

    log_info "Baixando imagens complementares (ClickHouse, Kafka)..."
    $DOCKER_COMPOSE pull clickhouse kafka

    # --remove-orphans apaga containers de serviços que saíram do compose
    # (Redis e Zookeeper, em instalações antigas).
    #
    # --wait espera todos os healthchecks passarem (em vez de sleeps fixos).
    # Os start_period no docker-compose.yml dão folga para a primeira subida.
    log_info "Iniciando containers e aguardando ficarem saudáveis (pode levar alguns minutos)..."
    if $DOCKER_COMPOSE up --help 2>/dev/null | grep -q -- '--wait'; then
        local wait_args=(--wait)
        if $DOCKER_COMPOSE up --help 2>/dev/null | grep -q -- '--wait-timeout'; then
            wait_args+=(--wait-timeout 600)
        fi
        if $DOCKER_COMPOSE up -d --remove-orphans "${wait_args[@]}"; then
            log_info "Todos os serviços estão saudáveis!"
        else
            log_warn "Algum serviço não ficou saudável a tempo."
        fi
    else
        # docker-compose v1 não tem --wait: faz polling dos healthchecks
        $DOCKER_COMPOSE up -d --remove-orphans
        local total ready=0
        total=$($DOCKER_COMPOSE config --services | grep -c .)
        for _ in $(seq 1 120); do
            ready=$(count_ready_services)
            [ "$ready" -ge "$total" ] && break
            echo -n "."
            sleep 5
        done
        echo ""
        if [ "$ready" -ge "$total" ]; then
            log_info "Todos os serviços estão saudáveis!"
        else
            log_warn "Apenas $ready de $total serviços ficaram saudáveis em 10 minutos."
        fi
    fi

    # Verificar status
    log_info "Status dos containers:"
    $DOCKER_COMPOSE ps
}

# Verificar saúde dos serviços pela API (complementa o healthcheck do Docker)
check_health() {
    log_info "Verificando saúde dos serviços..."

    local console_port orchestrator_port clickhouse_port
    console_port=$(env_get CONSOLE_HTTP_PORT 8000)
    orchestrator_port=$(env_get ORCHESTRATOR_HTTP_PORT 8080)
    clickhouse_port=$(env_get CLICKHOUSE_HTTP_PORT 8123)

    if curl -sf "http://localhost:${console_port}/api/v0/healthcheck" > /dev/null 2>&1; then
        log_info "✓ Console está saudável!"
    else
        log_warn "✗ Console não está respondendo (porta $console_port)"
        log_warn "Verifique os logs com: $DOCKER_COMPOSE logs akvorado-console"
    fi

    if curl -sf "http://localhost:${orchestrator_port}/api/v0/healthcheck" > /dev/null 2>&1; then
        log_info "✓ Orchestrator está saudável!"
    else
        log_warn "✗ Orchestrator não está respondendo (porta $orchestrator_port)"
        log_warn "Verifique os logs com: $DOCKER_COMPOSE logs akvorado-orchestrator"
    fi

    if curl -sf "http://localhost:${clickhouse_port}/ping" > /dev/null 2>&1; then
        log_info "✓ ClickHouse está saudável!"
    else
        log_warn "✗ ClickHouse não está respondendo (porta $clickhouse_port)"
    fi
}

# Exibir informações finais
show_info() {
    local console_port orchestrator_port clickhouse_port
    console_port=$(env_get CONSOLE_HTTP_PORT 8000)
    orchestrator_port=$(env_get ORCHESTRATOR_HTTP_PORT 8080)
    clickhouse_port=$(env_get CLICKHOUSE_HTTP_PORT 8123)

    log_info "========================================"
    log_info "Instalação concluída!"
    log_info "========================================"
    echo ""
    log_info "Serviços disponíveis:"
    log_info "  - Console Web: http://localhost:${console_port}"
    log_info "  - Orchestrator API: http://localhost:${orchestrator_port}"
    log_info "  - ClickHouse: http://localhost:${clickhouse_port}"
    echo ""
    log_info "Portas de entrada de flows:"
    log_info "  - NetFlow: UDP 2055"
    log_info "  - sFlow: UDP 6343"
    log_info "  - IPFIX: UDP 4739"
    echo ""
    log_info "Comandos úteis:"
    log_info "  - Verificação completa: ./scripts/check-health.sh"
    log_info "  - Ver status: ./scripts/manage.sh status"
    log_info "  - Ver logs: ./scripts/manage.sh logs [serviço]"
    log_info "  - Atualizar: ./scripts/manage.sh update"
    log_info "  - Parar serviços: ./scripts/manage.sh stop"
    echo ""
    if [ "$(env_get CLICKHOUSE_PASSWORD akvorado123)" = "akvorado123" ]; then
        log_warn "IMPORTANTE: a senha do ClickHouse ainda é a padrão (akvorado123)."
        log_warn "Rode 'sudo bash bootstrap.sh' para definir uma senha antes de usar em produção"
        log_warn "(ele atualiza o .env e regenera config/akvorado-orchestrator.yaml)."
        echo ""
    fi
}

# Main
main() {
    echo ""
    log_info "========================================"
    log_info "Instalação do Akvorado"
    log_info "========================================"
    echo ""

    check_root
    check_dependencies
    check_ports
    setup_environment
    detect_clickhouse_version
    download_geoip
    cleanup_legacy_configs
    start_services
    check_health
    show_info
}

# Executar
main
