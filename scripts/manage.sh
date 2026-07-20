#!/bin/bash

# Script de Gerenciamento do Akvorado
# Comandos úteis para administração do Akvorado

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Docker Compose command
if command -v docker-compose &> /dev/null; then
    DC="docker-compose"
else
    DC="docker compose"
fi

# Funções
show_help() {
    echo "Gerenciador do Akvorado"
    echo ""
    echo "Uso: ./manage.sh [comando]"
    echo ""
    echo "Comandos disponíveis:"
    echo "  start           - Inicia todos os serviços"
    echo "  stop            - Para todos os serviços"
    echo "  restart         - Reinicia todos os serviços"
    echo "  status          - Mostra status dos containers"
    echo "  logs [serviço]  - Exibe logs (opcional: especificar serviço)"
    echo "  update          - Atualiza imagens e reinicia"
    echo "  backup          - Faz backup dos dados"
    echo "  restore         - Restaura backup"
    echo "  clean           - Remove dados e recomeça"
    echo "  stats           - Mostra estatísticas de flows"
    echo "  health          - Verifica saúde dos serviços"
    echo "  geoip-update    - Atualiza bancos GeoIP"
    echo "  shell [serviço] - Abre shell em um container"
    echo ""
}

start_services() {
    echo -e "${GREEN}Iniciando serviços...${NC}"
    $DC up -d
    echo -e "${GREEN}Serviços iniciados!${NC}"
    sleep 5
    $DC ps
}

stop_services() {
    echo -e "${YELLOW}Parando serviços...${NC}"
    $DC stop
    echo -e "${GREEN}Serviços parados!${NC}"
}

restart_services() {
    echo -e "${YELLOW}Reiniciando serviços...${NC}"
    $DC restart
    echo -e "${GREEN}Serviços reiniciados!${NC}"
    sleep 5
    $DC ps
}

show_status() {
    echo -e "${BLUE}Status dos containers:${NC}"
    $DC ps
    echo ""
    echo -e "${BLUE}Uso de recursos:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
        $(docker ps --filter "name=akvorado" -q)
}

show_logs() {
    if [ -z "$1" ]; then
        echo -e "${BLUE}Logs de todos os serviços:${NC}"
        $DC logs --tail=100 -f
    else
        echo -e "${BLUE}Logs do serviço $1:${NC}"
        $DC logs --tail=100 -f "$1"
    fi
}

update_services() {
    echo -e "${YELLOW}Atualizando serviços...${NC}"
    $DC pull
    $DC up -d
    echo -e "${GREEN}Atualização concluída!${NC}"
}

backup_data() {
    local backup_dir="backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="akvorado_backup_${timestamp}.tar.gz"

    echo -e "${YELLOW}Criando backup...${NC}"
    mkdir -p "$backup_dir"

    # Para os serviços
    echo "Parando serviços..."
    $DC stop

    # Cria backup
    echo "Compactando dados..."
    tar -czf "$backup_dir/$backup_file" data/ config/ .env

    # Reinicia serviços
    echo "Reiniciando serviços..."
    $DC start

    echo -e "${GREEN}Backup criado: $backup_dir/$backup_file${NC}"
}

restore_backup() {
    local backup_dir="backups"

    if [ ! -d "$backup_dir" ]; then
        echo -e "${RED}Diretório de backup não encontrado!${NC}"
        exit 1
    fi

    echo -e "${BLUE}Backups disponíveis:${NC}"
    ls -lh "$backup_dir"/*.tar.gz 2>/dev/null || {
        echo -e "${RED}Nenhum backup encontrado!${NC}"
        exit 1
    }

    echo ""
    read -p "Digite o nome do arquivo de backup: " backup_file

    if [ ! -f "$backup_dir/$backup_file" ]; then
        echo -e "${RED}Arquivo não encontrado!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Restaurando backup...${NC}"

    # Para os serviços
    $DC down

    # Restaura backup
    echo "Descompactando dados..."
    tar -xzf "$backup_dir/$backup_file"

    # Inicia serviços
    $DC up -d

    echo -e "${GREEN}Backup restaurado com sucesso!${NC}"
}

clean_data() {
    echo -e "${RED}ATENÇÃO: Isto irá remover TODOS os dados!${NC}"
    read -p "Tem certeza? (digite 'yes' para confirmar): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Operação cancelada"
        exit 0
    fi

    echo -e "${YELLOW}Removendo todos os dados...${NC}"
    $DC down -v
    rm -rf data/*
    rm -rf logs/*

    echo -e "${GREEN}Dados removidos! Execute './manage.sh start' para recomeçar${NC}"
}

show_stats() {
    echo -e "${BLUE}Estatísticas do Akvorado:${NC}"
    echo ""

    # Conectar ao ClickHouse e mostrar estatísticas
    docker exec akvorado-clickhouse clickhouse-client --query="
        SELECT
            'Total de Flows' as metric,
            formatReadableQuantity(count()) as value
        FROM akvorado.flows
        UNION ALL
        SELECT
            'Flows (últimas 24h)' as metric,
            formatReadableQuantity(count()) as value
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 24 HOUR
        UNION ALL
        SELECT
            'Bytes Totais' as metric,
            formatReadableSize(sum(Bytes)) as value
        FROM akvorado.flows
        UNION ALL
        SELECT
            'Bytes (últimas 24h)' as metric,
            formatReadableSize(sum(Bytes)) as value
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 24 HOUR
        FORMAT Pretty
    " 2>/dev/null || echo -e "${YELLOW}Aguardando coleta de dados...${NC}"
}

check_health() {
    echo -e "${BLUE}Verificando saúde dos serviços:${NC}"
    echo ""

    # Array de serviços e suas portas de health
    declare -A services=(
        ["Console"]="8000"
        ["Orchestrator"]="8080"
        ["Inlet"]="8082"
        ["ClickHouse"]="8123"
        ["Redis"]="6379"
    )

    for service in "${!services[@]}"; do
        port="${services[$service]}"

        if nc -z localhost "$port" 2>/dev/null || timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/$port" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $service (porta $port)"
        else
            echo -e "  ${RED}✗${NC} $service (porta $port)"
        fi
    done
}

update_geoip() {
    echo -e "${BLUE}Atualização de bancos GeoIP${NC}"
    echo ""
    echo "Para atualizar, você precisa:"
    echo "1. Conta MaxMind: https://www.maxmind.com/en/geolite2/signup"
    echo "2. Baixar os arquivos:"
    echo "   - GeoLite2-ASN.mmdb"
    echo "   - GeoLite2-Country.mmdb"
    echo "   - GeoLite2-City.mmdb"
    echo "3. Copiar para: data/geoip/"
    echo ""
    read -p "Pressione Enter quando os arquivos estiverem prontos..."

    if [ -f "data/geoip/GeoLite2-ASN.mmdb" ]; then
        echo -e "${GREEN}✓ GeoLite2-ASN.mmdb encontrado${NC}"
    else
        echo -e "${RED}✗ GeoLite2-ASN.mmdb não encontrado${NC}"
    fi

    if [ -f "data/geoip/GeoLite2-Country.mmdb" ]; then
        echo -e "${GREEN}✓ GeoLite2-Country.mmdb encontrado${NC}"
    else
        echo -e "${RED}✗ GeoLite2-Country.mmdb não encontrado${NC}"
    fi

    if [ -f "data/geoip/GeoLite2-City.mmdb" ]; then
        echo -e "${GREEN}✓ GeoLite2-City.mmdb encontrado${NC}"
    else
        echo -e "${RED}✗ GeoLite2-City.mmdb não encontrado${NC}"
    fi

    echo ""
    echo "Reiniciando serviços para aplicar mudanças..."
    $DC restart
}

open_shell() {
    if [ -z "$1" ]; then
        echo -e "${RED}Especifique o serviço!${NC}"
        echo "Serviços disponíveis:"
        $DC ps --services
        exit 1
    fi

    echo -e "${BLUE}Abrindo shell em $1...${NC}"
    $DC exec "$1" /bin/sh || $DC exec "$1" /bin/bash
}

# Main
case "${1:-help}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        restart_services
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs "$2"
        ;;
    update)
        update_services
        ;;
    backup)
        backup_data
        ;;
    restore)
        restore_backup
        ;;
    clean)
        clean_data
        ;;
    stats)
        show_stats
        ;;
    health)
        check_health
        ;;
    geoip-update)
        update_geoip
        ;;
    shell)
        open_shell "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Comando desconhecido: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
