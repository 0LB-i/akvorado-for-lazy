#!/bin/bash

# Script de Verificação de Saúde do Akvorado
# Verifica se todos os componentes estão funcionando corretamente

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================"
echo -e "Verificação de Saúde - Akvorado"
echo -e "========================================${NC}"
echo ""

# Usar docker-compose ou docker compose
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# Lê uma porta do .env (com default), para respeitar portas personalizadas
env_port() {
    local value
    value=$(grep -E "^$1=" .env 2>/dev/null | tail -n1 | cut -d'=' -f2 | tr -d ' "')
    echo "${value:-$2}"
}

CLICKHOUSE_HTTP_PORT=$(env_port CLICKHOUSE_HTTP_PORT 8123)
ORCHESTRATOR_PORT=$(env_port ORCHESTRATOR_HTTP_PORT 8080)
CONSOLE_PORT=$(env_port CONSOLE_HTTP_PORT 8000)
# O inlet roda com network_mode: host e escuta direto na 8082
# (http.listen em config/akvorado-inlet.yaml), não há variável no .env.
INLET_PORT=8082

# /api/v0/healthcheck existe em todos os serviços do akvorado e retorna 503
# quando algum componente interno falha. -f faz o curl tratar 503 como erro.
akvorado_healthy() {
    curl -sf "http://localhost:$1/api/v0/healthcheck" > /dev/null 2>&1
}

# Conta erros nas últimas linhas de log de um serviço. Os logs do akvorado
# são JSON, com o nível em "level":"error" (ou fatal/panic).
count_log_errors() {
    $DOCKER_COMPOSE logs "$1" --tail=20 2>&1 | grep -cE '"level":"(error|fatal|panic)"' || true
}

# Verifica um serviço do akvorado exposto via HTTP
check_akvorado_service() {
    local label="$1" service="$2" port="$3" errors
    if akvorado_healthy "$port"; then
        echo -e "${GREEN}✓ $label está saudável (porta $port)${NC}"
        errors=$(count_log_errors "$service")
        if [ "$errors" -gt 0 ]; then
            echo -e "${YELLOW}⚠ $label tem $errors erro(s) nos logs recentes${NC}"
        else
            echo -e "${GREEN}✓ Sem erros nos logs do $label${NC}"
        fi
    else
        echo -e "${RED}✗ $label NÃO está saudável na porta $port${NC}"
        echo "  Veja: $DOCKER_COMPOSE logs $service"
    fi
}

# Contagens de containers. Não use grep "Up.*healthy": essa expressão também
# casa com "(unhealthy)" e conta containers doentes como saudáveis.
total_services=$($DOCKER_COMPOSE config --services 2>/dev/null | grep -c . || true)
count_healthy() {
    $DOCKER_COMPOSE ps 2>/dev/null | grep -c "(healthy)" || true
}

# 1. Verificar se todos os containers estão rodando
echo -e "${BLUE}[1/8] Status dos Containers${NC}"
echo "----------------------------------------"
$DOCKER_COMPOSE ps
echo ""

# 2. Verificar containers que não estão healthy
echo -e "${BLUE}[2/8] Verificando Containers Não-Saudáveis${NC}"
echo "----------------------------------------"
healthy_count=$(count_healthy)
if [ "$healthy_count" -lt "$total_services" ]; then
    echo -e "${YELLOW}⚠ $((total_services - healthy_count)) de ${total_services} container(s) ainda não estão healthy:${NC}"
    $DOCKER_COMPOSE ps 2>/dev/null | tail -n +2 | grep -v "(healthy)" || true
else
    echo -e "${GREEN}✓ Todos os containers estão saudáveis${NC}"
fi
echo ""

# 3. Verificar ClickHouse
echo -e "${BLUE}[3/8] ClickHouse${NC}"
echo "----------------------------------------"
if curl -sf "http://localhost:${CLICKHOUSE_HTTP_PORT}/ping" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ClickHouse está respondendo${NC}"

    # Verificar se está escutando em 0.0.0.0:9000
    if $DOCKER_COMPOSE exec -T clickhouse netstat -tln 2>/dev/null | grep -q "0.0.0.0:9000"; then
        echo -e "${GREEN}✓ ClickHouse escutando em 0.0.0.0:9000${NC}"
    else
        echo -e "${RED}✗ ClickHouse NÃO está escutando em 0.0.0.0:9000${NC}"
    fi

    # Verificar banco de dados
    if $DOCKER_COMPOSE exec -T clickhouse clickhouse-client --query "SHOW DATABASES" 2>/dev/null | grep -q "akvorado"; then
        echo -e "${GREEN}✓ Database 'akvorado' existe${NC}"
    else
        echo -e "${YELLOW}⚠ Database 'akvorado' não encontrado${NC}"
    fi
else
    echo -e "${RED}✗ ClickHouse NÃO está respondendo${NC}"
fi
echo ""

# 4. Verificar Kafka
echo -e "${BLUE}[4/8] Kafka${NC}"
echo "----------------------------------------"
if $DOCKER_COMPOSE exec -T kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Kafka respondendo na porta 9092${NC}"
else
    echo -e "${RED}✗ Kafka NÃO está respondendo na porta 9092${NC}"
fi
echo ""

# 5. Verificar Orchestrator
echo -e "${BLUE}[5/8] Akvorado Orchestrator${NC}"
echo "----------------------------------------"
check_akvorado_service "Orchestrator" akvorado-orchestrator "$ORCHESTRATOR_PORT"
echo ""

# 6. Verificar Inlet
echo -e "${BLUE}[6/8] Akvorado Inlet${NC}"
echo "----------------------------------------"
check_akvorado_service "Inlet" akvorado-inlet "$INLET_PORT"
echo ""

# 7. Verificar Outlet (não publica porta no host: usa o healthcheck do Docker)
echo -e "${BLUE}[7/8] Akvorado Outlet${NC}"
echo "----------------------------------------"
outlet_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' akvorado-outlet 2>/dev/null || echo "ausente")
case "$outlet_health" in
    healthy)
        echo -e "${GREEN}✓ Outlet está saudável${NC}"
        outlet_errors=$(count_log_errors akvorado-outlet)
        if [ "$outlet_errors" -gt 0 ]; then
            echo -e "${YELLOW}⚠ Outlet tem $outlet_errors erro(s) nos logs recentes${NC}"
        else
            echo -e "${GREEN}✓ Sem erros nos logs do Outlet${NC}"
        fi
        ;;
    starting)
        echo -e "${YELLOW}⚠ Outlet ainda está inicializando${NC}"
        ;;
    *)
        echo -e "${RED}✗ Outlet NÃO está saudável (estado: ${outlet_health})${NC}"
        echo "  Veja: $DOCKER_COMPOSE logs akvorado-outlet"
        ;;
esac
echo ""

# 8. Verificar Console
echo -e "${BLUE}[8/8] Akvorado Console${NC}"
echo "----------------------------------------"
check_akvorado_service "Console" akvorado-console "$CONSOLE_PORT"
echo ""

# Resumo Final
echo -e "${BLUE}========================================"
echo -e "Resumo"
echo -e "========================================${NC}"

healthy_count=$(count_healthy)
echo -e "Serviços saudáveis: ${GREEN}${healthy_count}/${total_services}${NC}"
echo ""

if [ "$total_services" -gt 0 ] && [ "$healthy_count" -eq "$total_services" ]; then
    echo -e "${GREEN}✓✓✓ Tudo está funcionando perfeitamente! ✓✓✓${NC}"
    echo ""
    echo -e "${BLUE}Interface Web:${NC} http://localhost:${CONSOLE_PORT}"
    echo -e "${BLUE}Orchestrator API:${NC} http://localhost:${ORCHESTRATOR_PORT}"
    echo ""
    echo -e "${BLUE}Portas para enviar flows:${NC}"
    echo -e "  - NetFlow: UDP 2055"
    echo -e "  - sFlow: UDP 6343"
    echo -e "  - IPFIX: UDP 4739"
else
    echo -e "${YELLOW}⚠ Alguns serviços ainda estão inicializando ou com problemas${NC}"
    echo ""
    echo "Execute para ver detalhes:"
    echo "  $DOCKER_COMPOSE logs <nome-do-servico>"
    echo ""
    echo "Serviços disponíveis:"
    $DOCKER_COMPOSE config --services 2>/dev/null | sed 's/^/  - /'
fi

echo ""
echo -e "${BLUE}========================================${NC}"
