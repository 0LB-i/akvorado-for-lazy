#!/bin/bash

# Script para corrigir conexão Kafka do Inlet
# Força recriação do container e valida conectividade

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Fix Inlet Kafka Connection${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Usar docker-compose ou docker compose
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    DOCKER_COMPOSE="docker compose"
fi

# 1. Verificar se Kafka está acessível no host
echo -e "${BLUE}[1/6] Verificando se Kafka está acessível em localhost:9092...${NC}"
if nc -zv localhost 9092 2>&1 | grep -q "succeeded\|open"; then
    echo -e "${GREEN}✓ Kafka está acessível em localhost:9092${NC}"
else
    echo -e "${RED}✗ Kafka NÃO está acessível em localhost:9092${NC}"
    echo -e "${YELLOW}Verificando se está acessível via IP do container...${NC}"

    # Tentar via IP do container Kafka
    kafka_ip=$($DOCKER_COMPOSE exec kafka hostname -i 2>/dev/null | tr -d '\r\n')
    if [ -n "$kafka_ip" ]; then
        echo -e "${YELLOW}IP do Kafka: $kafka_ip${NC}"
        if nc -zv $kafka_ip 9092 2>&1 | grep -q "succeeded\|open"; then
            echo -e "${YELLOW}⚠ Kafka está acessível via IP $kafka_ip mas não via localhost${NC}"
            echo -e "${YELLOW}Isso pode indicar um problema de configuração do Kafka${NC}"
        fi
    fi
fi
echo ""

# 2. Parar o inlet
echo -e "${BLUE}[2/6] Parando container inlet...${NC}"
$DOCKER_COMPOSE stop akvorado-inlet
echo -e "${GREEN}✓ Container inlet parado${NC}"
echo ""

# 3. Remover o inlet
echo -e "${BLUE}[3/6] Removendo container inlet...${NC}"
$DOCKER_COMPOSE rm -f akvorado-inlet
echo -e "${GREEN}✓ Container inlet removido${NC}"
echo ""

# 4. Recriar o inlet
echo -e "${BLUE}[4/6] Recriando container inlet...${NC}"
$DOCKER_COMPOSE up -d akvorado-inlet --force-recreate
echo -e "${GREEN}✓ Container inlet recriado${NC}"
echo ""

# 5. Aguardar inicialização
echo -e "${BLUE}[5/6] Aguardando inicialização (15 segundos)...${NC}"
sleep 15
echo -e "${GREEN}✓ Aguardado${NC}"
echo ""

# 6. Verificar configuração e logs
echo -e "${BLUE}[6/6] Verificando configuração e logs...${NC}"
echo ""

echo -e "${YELLOW}Configuração do Kafka no container:${NC}"
$DOCKER_COMPOSE exec akvorado-inlet cat /etc/akvorado/config.yaml | grep -A3 "kafka:" || echo "Não foi possível ler a configuração"
echo ""

echo -e "${YELLOW}Últimas 30 linhas dos logs do inlet:${NC}"
echo "----------------------------------------"
$DOCKER_COMPOSE logs akvorado-inlet --tail=30
echo "----------------------------------------"
echo ""

echo -e "${YELLOW}Procurando por referências ao Kafka nos logs:${NC}"
kafka_refs=$($DOCKER_COMPOSE logs akvorado-inlet --tail=50 | grep -i "kafka\|broker" || echo "Nenhuma referência encontrada")
echo "$kafka_refs"
echo ""

# 7. Verificar se inlet está escutando nas portas UDP
echo -e "${BLUE}Verificando portas UDP do inlet...${NC}"
if netstat -uln 2>/dev/null | grep -E ":(2055|6343|4739)" || ss -uln 2>/dev/null | grep -E ":(2055|6343|4739)"; then
    echo -e "${GREEN}✓ Inlet escutando nas portas UDP${NC}"
else
    echo -e "${YELLOW}⚠ Não foi possível verificar portas UDP com netstat/ss${NC}"
fi
echo ""

# 8. Status final
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Status Final${NC}"
echo -e "${BLUE}========================================${NC}"

if $DOCKER_COMPOSE logs akvorado-inlet --tail=20 | grep -q "localhost:9092"; then
    echo -e "${GREEN}✓ Logs mostram tentativa de conexão com localhost:9092${NC}"
elif $DOCKER_COMPOSE logs akvorado-inlet --tail=20 | grep -q "kafka:9092"; then
    echo -e "${RED}✗ Logs ainda mostram tentativa de conexão com kafka:9092${NC}"
    echo -e "${YELLOW}O container pode estar usando uma configuração antiga ou cached${NC}"
else
    echo -e "${YELLOW}⚠ Não foi possível identificar o broker nos logs recentes${NC}"
fi

# Verificar se há erros de conexão
if $DOCKER_COMPOSE logs akvorado-inlet --tail=20 | grep -qi "error\|failed\|refused"; then
    echo -e "${RED}✗ Erros encontrados nos logs${NC}"
    echo -e "${YELLOW}Execute para mais detalhes: docker compose logs akvorado-inlet --tail=100${NC}"
else
    echo -e "${GREEN}✓ Nenhum erro aparente nos logs recentes${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "Script concluído!"
echo ""
echo -e "Se o problema persistir, verifique:"
echo -e "1. Kafka precisa estar configurado para aceitar conexões externas"
echo -e "2. Verifique KAFKA_ADVERTISED_LISTENERS no docker-compose.yml"
echo -e "3. Teste manualmente: ${YELLOW}nc -zv localhost 9092${NC}"
echo -e "${BLUE}========================================${NC}"
