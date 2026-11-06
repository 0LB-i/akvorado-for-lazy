#!/bin/bash

# Script para verificar serviços do Akvorado remotamente
# Uso: ./remote-check.sh [opção]

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Servidor remoto (defina via variáveis de ambiente antes de rodar o script,
# ex: REMOTE_HOST=meuservidor.com REMOTE_USER=usuario ./remote-check.sh)
# Autenticação é via chave SSH (configure sua chave pública no servidor antes de usar).
REMOTE_HOST="${REMOTE_HOST:?Defina a variável de ambiente REMOTE_HOST}"
REMOTE_USER="${REMOTE_USER:?Defina a variável de ambiente REMOTE_USER}"
# Diretório da instalação no servidor (default = onde o bootstrap.sh instala)
REMOTE_DIR="${REMOTE_DIR:-/opt/akvorado}"
# Portas HTTP (ajuste se mudou ORCHESTRATOR_HTTP_PORT/CONSOLE_HTTP_PORT no .env)
ORCHESTRATOR_PORT="${ORCHESTRATOR_PORT:-8080}"
INLET_PORT="${INLET_PORT:-8082}"
CONSOLE_PORT="${CONSOLE_PORT:-8000}"

# Versão do diretório escapada para uso seguro no comando remoto
REMOTE_DIR_Q=$(printf '%q' "$REMOTE_DIR")

echo "=========================================="
echo "  Akvorado - Verificação Remota"
echo "=========================================="
echo ""

# Função para executar comandos remotos
remote_exec() {
    ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_HOST" "$1"
}

# Verificar status dos containers
check_containers() {
    echo -e "${YELLOW}[1/6] Verificando containers...${NC}"
    remote_exec "cd $REMOTE_DIR_Q && docker compose ps"
    echo ""
}

# Verificar saúde dos serviços
check_health() {
    echo -e "${YELLOW}[2/6] Verificando saúde dos serviços...${NC}"

    # /api/v0/healthcheck existe em todos os serviços do akvorado e retorna
    # 503 quando algum componente interno falha; -f faz o curl sair com erro
    # nesse caso (sem ele, um 503 contaria como sucesso).
    local name port
    for entry in "Orchestrator:$ORCHESTRATOR_PORT" "Inlet:$INLET_PORT" "Console:$CONSOLE_PORT"; do
        name="${entry%%:*}"
        port="${entry##*:}"
        echo "$name (porta $port):"
        if remote_exec "curl -sf http://localhost:${port}/api/v0/healthcheck"; then
            echo -e "\n${GREEN}OK${NC}"
        else
            echo -e "${RED}FALHOU${NC}"
        fi
        echo ""
    done

    echo "ClickHouse:"
    remote_exec "docker exec akvorado-clickhouse clickhouse-client --query='SELECT 1'" || echo -e "${RED}FALHOU${NC}"
    echo ""
}

# Verificar logs recentes
check_logs() {
    echo -e "${YELLOW}[3/6] Verificando logs recentes (últimas 20 linhas)...${NC}"

    echo "=== Orchestrator ==="
    remote_exec "cd $REMOTE_DIR_Q && docker compose logs --tail=20 akvorado-orchestrator"

    echo -e "\n=== Outlet ==="
    remote_exec "cd $REMOTE_DIR_Q && docker compose logs --tail=20 akvorado-outlet"

    echo -e "\n=== Inlet ==="
    remote_exec "cd $REMOTE_DIR_Q && docker compose logs --tail=20 akvorado-inlet"
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

    ERRORS=$(remote_exec "cd $REMOTE_DIR_Q && docker compose logs --tail=100 | grep -i 'error\|fatal\|panic' | tail -20")

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
