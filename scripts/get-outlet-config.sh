#!/bin/bash

# Script para baixar configuração oficial do Akvorado Outlet
# Extrai a config do quickstart oficial e mostra como configurar

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Baixando configuração oficial Akvorado${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Criar diretório temporário
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo -e "${YELLOW}Baixando quickstart tarball...${NC}"
curl -sL https://github.com/akvorado/akvorado/releases/latest/download/docker-compose-quickstart.tar.gz | tar zxf -

echo -e "${GREEN}✓ Download completo${NC}"
echo ""

# Mostrar configuração do outlet
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configuração Oficial do Outlet:${NC}"
echo -e "${BLUE}========================================${NC}"
cat config/outlet.yaml
echo ""

# Mostrar serviço outlet no docker-compose
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Serviço Outlet no Docker Compose:${NC}"
echo -e "${BLUE}========================================${NC}"
grep -A30 "outlet:" docker/docker-compose.yml || echo "Outlet não encontrado no docker-compose"
echo ""

# Mostrar configuração principal
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configuração Principal (primeiras 50 linhas):${NC}"
echo -e "${BLUE}========================================${NC}"
head -50 config/akvorado.yaml
echo ""

# Copiar configs para diretório de trabalho se solicitado
echo -e "${YELLOW}Arquivos baixados em: $TEMP_DIR${NC}"
echo -e "${YELLOW}Para copiar para seu projeto:${NC}"
echo -e "  cp $TEMP_DIR/config/outlet.yaml ./config/"
echo -e "  cp $TEMP_DIR/config/akvorado.yaml ./config/"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Concluído!${NC}"
echo -e "${BLUE}========================================${NC}"
