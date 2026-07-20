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

# 1. Verificar se todos os containers estão rodando
echo -e "${BLUE}[1/8] Status dos Containers${NC}"
echo "----------------------------------------"
$DOCKER_COMPOSE ps
echo ""

# 2. Verificar containers que não estão healthy
echo -e "${BLUE}[2/8] Verificando Containers Não-Saudáveis${NC}"
echo "----------------------------------------"
unhealthy=$($DOCKER_COMPOSE ps | grep -v "Up.*healthy" | grep "Up" | wc -l || true)
if [ "$unhealthy" -gt 1 ]; then
    echo -e "${YELLOW}⚠ Alguns containers ainda estão inicializando...${NC}"
else
    echo -e "${GREEN}✓ Todos os containers estão saudáveis${NC}"
fi
echo ""

# 3. Verificar ClickHouse
echo -e "${BLUE}[3/8] ClickHouse${NC}"
echo "----------------------------------------"
if curl -s http://localhost:8123/ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ ClickHouse está respondendo${NC}"

    # Verificar se está escutando em 0.0.0.0:9000
    if $DOCKER_COMPOSE exec clickhouse netstat -tln 2>/dev/null | grep -q "0.0.0.0:9000"; then
        echo -e "${GREEN}✓ ClickHouse escutando em 0.0.0.0:9000${NC}"
    else
        echo -e "${RED}✗ ClickHouse NÃO está escutando em 0.0.0.0:9000${NC}"
    fi

    # Verificar banco de dados
    if $DOCKER_COMPOSE exec clickhouse clickhouse-client --query "SHOW DATABASES" 2>/dev/null | grep -q "akvorado"; then
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
kafka_status=$($DOCKER_COMPOSE logs kafka --tail=50 2>&1 | grep -c "started (kafka.server.KafkaServer)" || true)
if [ "$kafka_status" -gt 0 ]; then
    echo -e "${GREEN}✓ Kafka está rodando${NC}"
else
    echo -e "${YELLOW}⚠ Kafka pode estar inicializando ainda${NC}"
fi

# Verificar se Kafka está escutando
if $DOCKER_COMPOSE exec kafka nc -zv localhost 9092 2>&1 | grep -q "succeeded"; then
    echo -e "${GREEN}✓ Kafka escutando na porta 9092${NC}"
else
    echo -e "${RED}✗ Kafka NÃO está escutando na porta 9092${NC}"
fi
echo ""

# 5. Verificar Redis
echo -e "${BLUE}[5/8] Redis${NC}"
echo "----------------------------------------"
if $DOCKER_COMPOSE exec redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo -e "${GREEN}✓ Redis está respondendo${NC}"
else
    echo -e "${RED}✗ Redis NÃO está respondendo${NC}"
fi
echo ""

# 6. Verificar Orchestrator
echo -e "${BLUE}[6/8] Akvorado Orchestrator${NC}"
echo "----------------------------------------"
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Orchestrator está respondendo${NC}"

    # Verificar logs por erros
    orch_errors=$($DOCKER_COMPOSE logs akvorado-orchestrator --tail=20 2>&1 | grep -c "Error:" || true)
    if [ "$orch_errors" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Orchestrator tem $orch_errors erro(s) nos logs recentes${NC}"
    else
        echo -e "${GREEN}✓ Sem erros nos logs do Orchestrator${NC}"
    fi
else
    echo -e "${RED}✗ Orchestrator NÃO está respondendo${NC}"
fi
echo ""

# 7. Verificar Inlet
echo -e "${BLUE}[7/8] Akvorado Inlet${NC}"
echo "----------------------------------------"
if curl -s http://localhost:8082/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Inlet está respondendo${NC}"

    # Verificar logs por erros
    inlet_errors=$($DOCKER_COMPOSE logs akvorado-inlet --tail=20 2>&1 | grep -c "Error:" || true)
    if [ "$inlet_errors" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Inlet tem $inlet_errors erro(s) nos logs recentes${NC}"
    else
        echo -e "${GREEN}✓ Sem erros nos logs do Inlet${NC}"
    fi
else
    echo -e "${RED}✗ Inlet NÃO está respondendo${NC}"
fi
echo ""

# 8. Verificar Console
echo -e "${BLUE}[8/8] Akvorado Console${NC}"
echo "----------------------------------------"
# Obter porta do console do .env
console_port=$(grep CONSOLE_HTTP_PORT .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ')
console_port=${console_port:-8000}

if curl -s http://localhost:${console_port}/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Console está respondendo (porta ${console_port})${NC}"

    # Verificar logs por erros
    console_errors=$($DOCKER_COMPOSE logs akvorado-console --tail=20 2>&1 | grep -c '"level":"error"' || true)
    if [ "$console_errors" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Console tem $console_errors erro(s) nos logs recentes${NC}"
    else
        echo -e "${GREEN}✓ Sem erros nos logs do Console${NC}"
    fi
else
    echo -e "${RED}✗ Console NÃO está respondendo na porta ${console_port}${NC}"
fi
echo ""

# Resumo Final
echo -e "${BLUE}========================================"
echo -e "Resumo"
echo -e "========================================${NC}"

# Contar serviços saudáveis
healthy_count=$($DOCKER_COMPOSE ps | grep -c "Up.*healthy" || true)
total_services=7

echo -e "Serviços saudáveis: ${GREEN}${healthy_count}/${total_services}${NC}"
echo ""

if [ "$healthy_count" -eq "$total_services" ]; then
    echo -e "${GREEN}✓✓✓ Tudo está funcionando perfeitamente! ✓✓✓${NC}"
    echo ""
    echo -e "${BLUE}Interface Web:${NC} http://localhost:${console_port}"
    echo -e "${BLUE}Orchestrator API:${NC} http://localhost:8080"
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
    echo "  - clickhouse"
    echo "  - kafka"
    echo "  - redis"
    echo "  - zookeeper"
    echo "  - akvorado-orchestrator"
    echo "  - akvorado-inlet"
    echo "  - akvorado-console"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
