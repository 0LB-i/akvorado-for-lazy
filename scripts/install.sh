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
        if command -v docker-compose &> /dev/null; then
            log_info "Docker Compose encontrado: $(docker-compose --version)"
        else
            log_info "Docker Compose encontrado: $(docker compose version)"
        fi
    fi

    # Verificar Git
    if ! command -v git &> /dev/null; then
        log_warn "Git não está instalado (opcional)"
    fi

    # Verificar curl
    if ! command -v curl &> /dev/null; then
        log_warn "curl não está instalado (recomendado para download de GeoIP)"
    fi

    if [ $missing_deps -eq 1 ]; then
        log_error "Instale as dependências faltantes e execute novamente"
        log_info "Para instalar Docker: https://docs.docker.com/engine/install/"
        exit 1
    fi
}

# Verificar portas disponíveis
check_ports() {
    log_info "Verificando portas disponíveis..."

    local ports=(8000 8080 8081 8082 8123 9000 6379 9092 2181 2055 6343 4739)
    local port_in_use=0

    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
            log_warn "Porta $port já está em uso"
            port_in_use=1
        fi
    done

    if [ $port_in_use -eq 1 ]; then
        log_warn "Algumas portas estão em uso. Edite o arquivo .env para usar portas diferentes."
        read -p "Deseja continuar mesmo assim? (s/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
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

    # Criar diretórios necessários
    log_info "Criando diretórios..."
    mkdir -p data/{clickhouse,redis,kafka,zookeeper,geoip}
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

    # Kafka precisa de permissões específicas (uid:gid 1000:1000)
    log_info "Configurando permissões do Kafka..."
    chown -R 1000:1000 data/kafka 2>/dev/null || log_warn "Não foi possível ajustar permissões do Kafka (pode precisar de root)"
}

# Download GeoIP databases
download_geoip() {
    log_info "Configurando bancos de dados GeoIP..."

    if [ -f data/geoip/GeoLite2-ASN.mmdb ] && [ -f data/geoip/GeoLite2-Country.mmdb ]; then
        log_info "Bancos de dados GeoIP já presentes em data/geoip/"
        return
    fi

    # Reaproveita a license key se já estiver salva no .env de uma
    # instalação anterior, para não perguntar de novo
    local license_key
    license_key=$(grep -E '^MAXMIND_LICENSE_KEY=' .env 2>/dev/null | cut -d'=' -f2-)

    if [ -z "$license_key" ]; then
        log_warn "Bancos de dados GeoIP (MaxMind GeoLite2) não encontrados"
        log_info "São gratuitos, mas exigem uma conta + license key MaxMind:"
        log_info "  https://www.maxmind.com/en/geolite2/signup"
        echo ""
        read -p "Baixar os bancos GeoIP agora? (s/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log_warn "Pulando GeoIP. O Akvorado funcionará sem informações de país/ASN."
            log_info "Você pode configurar depois - veja GEOIP_SETUP.md"
            return
        fi

        read -p "MaxMind License Key: " license_key
        if [ -z "$license_key" ]; then
            log_warn "License key vazia, pulando GeoIP."
            return
        fi

        # Salva no .env para não perguntar de novo em uma próxima instalação
        grep -v -E '^MAXMIND_LICENSE_KEY=' .env > .env.tmp || true
        { cat .env.tmp; echo "MAXMIND_LICENSE_KEY=${license_key}"; } > .env
        rm -f .env.tmp
    else
        log_info "Usando MAXMIND_LICENSE_KEY salva em .env"
    fi

    local tmp_dir edition failed
    tmp_dir=$(mktemp -d)
    failed=0

    for edition in GeoLite2-ASN GeoLite2-Country GeoLite2-City; do
        log_info "Baixando ${edition}..."
        if curl -sfL -o "${tmp_dir}/${edition}.tar.gz" \
            "https://download.maxmind.com/app/geoip_download?edition_id=${edition}&license_key=${license_key}&suffix=tar.gz"; then
            tar -xzf "${tmp_dir}/${edition}.tar.gz" -C "$tmp_dir"
        else
            log_warn "Falha ao baixar ${edition} (license key inválida ou sem conexão?)"
            failed=1
        fi
    done

    find "$tmp_dir" -name "*.mmdb" -exec cp -f {} data/geoip/ \;
    rm -rf "$tmp_dir"

    if [ -f data/geoip/GeoLite2-ASN.mmdb ]; then
        log_info "Bancos de dados GeoIP prontos:"
        ls -1 data/geoip/*.mmdb | sed 's/^/  - /'
    elif [ $failed -eq 1 ]; then
        log_warn "Não foi possível baixar os bancos GeoIP. O Akvorado funcionará sem GeoIP."
    fi
}

# Criar configurações adicionais
create_configs() {
    log_info "Criando configurações adicionais..."

    # Criar diretório clickhouse se não existir
    mkdir -p config/clickhouse

    # ClickHouse custom config
    if [ ! -f config/clickhouse/users.xml ]; then
        log_info "Criando configuração customizada do ClickHouse..."
        cat > config/clickhouse/users.xml <<EOF
<?xml version="1.0"?>
<clickhouse>
    <profiles>
        <default>
            <max_memory_usage>10000000000</max_memory_usage>
            <use_uncompressed_cache>0</use_uncompressed_cache>
            <load_balancing>random</load_balancing>
        </default>
    </profiles>
    <quotas>
        <default>
            <interval>
                <duration>3600</duration>
                <queries>0</queries>
                <errors>0</errors>
                <result_rows>0</result_rows>
                <read_rows>0</read_rows>
                <execution_time>0</execution_time>
            </interval>
        </default>
    </quotas>
</clickhouse>
EOF
    fi
}

# Iniciar serviços
start_services() {
    log_info "Iniciando serviços do Akvorado..."

    # Usar docker-compose ou docker compose dependendo da versão
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        DOCKER_COMPOSE="docker compose"
    fi

    # Build e pull das imagens
    log_info "Construindo imagem do Akvorado (isso pode levar alguns minutos)..."
    $DOCKER_COMPOSE build

    log_info "Baixando imagens complementares (ClickHouse, Redis, Kafka)..."
    $DOCKER_COMPOSE pull clickhouse redis kafka zookeeper

    # Iniciar serviços
    log_info "Iniciando containers..."
    $DOCKER_COMPOSE up -d

    # Aguardar inicialização
    log_info "Aguardando inicialização dos serviços..."
    log_info "Aguardando Zookeeper (10s)..."
    sleep 10

    log_info "Aguardando Kafka inicializar (pode levar até 60s)..."
    local kafka_ready=0
    for i in {1..30}; do
        if $DOCKER_COMPOSE logs kafka 2>&1 | grep -q "started (kafka.server.KafkaServer)"; then
            log_info "Kafka está pronto!"
            kafka_ready=1
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""

    if [ $kafka_ready -eq 0 ]; then
        log_warn "Kafka ainda está inicializando, mas continuando..."
    fi

    log_info "Aguardando ClickHouse e Orchestrator (20s)..."
    sleep 20

    # Verificar status
    log_info "Verificando status dos containers..."
    $DOCKER_COMPOSE ps
}

# Verificar saúde dos serviços
check_health() {
    log_info "Verificando saúde dos serviços..."

    # Obter porta do console do .env
    local console_port=$(grep CONSOLE_HTTP_PORT .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    console_port=${console_port:-8000}

    # Verificar Console
    local max_attempts=30
    local attempt=0
    log_info "Verificando Console (porta $console_port)..."

    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:${console_port}/health > /dev/null 2>&1; then
            log_info "✓ Console está saudável!"
            break
        fi

        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
            log_warn "✗ Console ainda não respondeu após ${max_attempts} tentativas"
            log_warn "Verifique os logs com: docker compose logs akvorado-console"
        else
            echo -n "."
            sleep 2
        fi
    done
    echo ""

    # Verificar Orchestrator
    log_info "Verificando Orchestrator..."
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        log_info "✓ Orchestrator está saudável!"
    else
        log_warn "✗ Orchestrator não está respondendo"
        log_warn "Verifique os logs com: docker compose logs akvorado-orchestrator"
    fi

    # Verificar ClickHouse
    log_info "Verificando ClickHouse..."
    if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
        log_info "✓ ClickHouse está saudável!"
    else
        log_warn "✗ ClickHouse não está respondendo"
    fi
}

# Exibir informações finais
show_info() {
    # Obter porta do console do .env
    local console_port=$(grep CONSOLE_HTTP_PORT .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
    console_port=${console_port:-8000}

    log_info "========================================"
    log_info "Instalação concluída com sucesso!"
    log_info "========================================"
    echo ""
    log_info "Serviços disponíveis:"
    log_info "  - Console Web: http://localhost:${console_port}"
    log_info "  - Orchestrator API: http://localhost:8080"
    log_info "  - ClickHouse: http://localhost:8123"
    log_info "  - Kafka: localhost:9092"
    echo ""
    log_info "Portas de entrada de flows:"
    log_info "  - NetFlow: UDP 2055"
    log_info "  - sFlow: UDP 6343"
    log_info "  - IPFIX: UDP 4739"
    echo ""
    log_info "Comandos úteis:"
    log_info "  - Ver status: docker compose ps"
    log_info "  - Ver logs: docker compose logs -f"
    log_info "  - Ver logs de um serviço: docker compose logs -f akvorado-console"
    log_info "  - Parar serviços: docker compose stop"
    log_info "  - Reiniciar: docker compose restart"
    log_info "  - Remover tudo: docker compose down -v"
    echo ""
    log_info "Verificar se todos os serviços estão saudáveis:"
    log_info "  docker compose ps"
    log_info "  (Todos devem estar 'Up' e '(healthy)')"
    echo ""
    log_warn "IMPORTANTE: Mude as senhas padrão no arquivo .env antes de usar em produção!"
    echo ""
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
    download_geoip
    create_configs
    start_services
    check_health
    show_info
}

# Executar
main
