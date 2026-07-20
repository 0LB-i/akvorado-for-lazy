#!/bin/bash

# Script para verificar serviços do Akvorado remotamente
# Uso: ./remote-check.sh [opção]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Servidor remoto
REMOTE_HOST="170.244.221.231"
REMOTE_USER="diogenes"
REMOTE_PASS="Bd121012%+"

echo "=========================================="
echo "  Akvorado - Verificação Remota"
echo "=========================================="
echo ""

# Função para executar comandos remotos
remote_exec() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$1"
}

# Verificar status dos containers
check_containers() {
    echo -e "${YELLOW}[1/6] Verificando containers...${NC}"
    remote_exec "cd /root/akvorado && docker compose ps"
    echo ""
}

# Verificar saúde dos serviços
check_health() {
    echo -e "${YELLOW}[2/6] Verificando saúde dos serviços...${NC}"

    echo "Orchestrator:"
    remote_exec "curl -s http://localhost:8080/api/v0/orchestrator/healthcheck" || echo -e "${RED}FALHOU${NC}"

    echo -e "\nConsole:"
    remote_exec "curl -s http://localhost:8000/health" || echo -e "${RED}FALHOU${NC}"

    echo -e "\nClickHouse:"
    remote_exec "docker exec akvorado-clickhouse clickhouse-client --query='SELECT 1'" || echo -e "${RED}FALHOU${NC}"
    echo ""
}

# Verificar logs recentes
check_logs() {
    echo -e "${YELLOW}[3/6] Verificando logs recentes (últimas 20 linhas)...${NC}"

    echo "=== Orchestrator ==="
    remote_exec "cd /root/akvorado && docker compose logs --tail=20 akvorado-orchestrator"

    echo -e "\n=== Outlet ==="
    remote_exec "cd /root/akvorado && docker compose logs --tail=20 akvorado-outlet"

    echo -e "\n=== Inlet ==="
    remote_exec "cd /root/akvorado && docker compose logs --tail=20 akvorado-inlet"
    echo ""
}

# Verificar estatísticas de flows
check_flows() {
    echo -e "${YELLOW}[4/6] Verificando estatísticas de flows...${NC}"

    echo "Total de flows armazenados:"
    remote_exec "docker exec akvorado-clickhouse clickhouse-client --query='SELECT count() FROM akvorado.flows FORMAT Pretty'"

    echo -e "\nFlows das últimas 24 horas:"
    remote_exec "docker exec akvorado-clickhouse clickhouse-client --query=\"SELECT count() FROM akvorado.flows WHERE TimeReceived > now() - INTERVAL 24 HOUR FORMAT Pretty\""

    echo -e "\nTop 10 IPs de origem (últimas 24h):"
    remote_exec "docker exec akvorado-clickhouse clickhouse-client --query=\"SELECT SrcAddr, count() as flows, sum(Bytes) as total_bytes FROM akvorado.flows WHERE TimeReceived > now() - INTERVAL 24 HOUR GROUP BY SrcAddr ORDER BY total_bytes DESC LIMIT 10 FORMAT Pretty\""
    echo ""
}

# Verificar uso de recursos
check_resources() {
    echo -e "${YELLOW}[5/6] Verificando uso de recursos...${NC}"
    remote_exec "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'"
    echo ""
}

# Verificar erros críticos
check_errors() {
    echo -e "${YELLOW}[6/6] Procurando por erros críticos...${NC}"

    ERRORS=$(remote_exec "cd /root/akvorado && docker compose logs --tail=100 | grep -i 'error\|fatal\|panic' | tail -20")

    if [ -z "$ERRORS" ]; then
        echo -e "${GREEN}Nenhum erro crítico encontrado nos últimos logs${NC}"
    else
        echo -e "${RED}Erros encontrados:${NC}"
        echo "$ERRORS"
    fi
    echo ""
}

# Menu de opções
case "${1:-all}" in
    containers|c)
        check_containers
        ;;
    health|h)
        check_health
        ;;
    logs|l)
        check_logs
        ;;
    flows|f)
        check_flows
        ;;
    resources|r)
        check_resources
        ;;
    errors|e)
        check_errors
        ;;
    all)
        check_containers
        check_health
        check_logs
        check_flows
        check_resources
        check_errors
        ;;
    *)
        echo "Uso: $0 [opção]"
        echo ""
        echo "Opções:"
        echo "  all (padrão)  - Executa todas as verificações"
        echo "  containers|c  - Status dos containers"
        echo "  health|h      - Saúde dos serviços"
        echo "  logs|l        - Logs recentes"
        echo "  flows|f       - Estatísticas de flows"
        echo "  resources|r   - Uso de recursos"
        echo "  errors|e      - Erros críticos"
        exit 1
        ;;
esac

echo -e "${GREEN}=========================================="
echo "  Verificação concluída!"
echo "==========================================${NC}"
