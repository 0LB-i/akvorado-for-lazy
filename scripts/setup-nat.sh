#!/bin/bash

# Script para configurar SRCNAT para tráfego Docker sair com IP do servidor
# Isso permite que requisições SNMP dos containers Docker saiam com o IP do servidor (170.244.221.231)
# ao invés do IP interno do Docker (172.25.0.0/16)

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Configurando SRCNAT para Docker${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Configurações
DOCKER_SUBNET="172.25.0.0/16"
SERVER_IP="170.244.221.231"
ROUTER_IP="10.0.0.2"

echo -e "${YELLOW}Configurações:${NC}"
echo "  Docker subnet: $DOCKER_SUBNET"
echo "  Server IP: $SERVER_IP"
echo "  Router IP: $ROUTER_IP"
echo ""

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
   echo -e "${RED}Este script precisa ser executado como root${NC}"
   echo "Use: sudo $0"
   exit 1
fi

# Verificar se iptables está instalado
if ! command -v iptables &> /dev/null; then
    echo -e "${RED}iptables não está instalado${NC}"
    exit 1
fi

echo -e "${YELLOW}Verificando regras existentes...${NC}"
if iptables -t nat -C POSTROUTING -s $DOCKER_SUBNET ! -d $DOCKER_SUBNET -j SNAT --to-source $SERVER_IP 2>/dev/null; then
    echo -e "${GREEN}✓ Regra SRCNAT já existe${NC}"
else
    echo -e "${YELLOW}Adicionando regra SRCNAT (para todo tráfego externo)...${NC}"
    # Use -I (insert) ao invés de -A (append) para que a regra fique ANTES das regras MASQUERADE do Docker
    iptables -t nat -I POSTROUTING 1 -s $DOCKER_SUBNET ! -d $DOCKER_SUBNET -j SNAT --to-source $SERVER_IP
    echo -e "${GREEN}✓ Regra SRCNAT adicionada no início da chain${NC}"
fi

echo ""
echo -e "${YELLOW}Regras NAT atuais:${NC}"
iptables -t nat -L POSTROUTING -n -v | grep -E "$DOCKER_SUBNET|Chain"

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Tornando regra persistente...${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Detectar sistema de init e tornar persistente
if command -v netfilter-persistent &> /dev/null; then
    echo -e "${YELLOW}Usando netfilter-persistent...${NC}"
    netfilter-persistent save
    echo -e "${GREEN}✓ Regras salvas com netfilter-persistent${NC}"
elif command -v iptables-save &> /dev/null; then
    echo -e "${YELLOW}Salvando com iptables-save...${NC}"

    # Criar diretório se não existir
    mkdir -p /etc/iptables

    # Salvar regras
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}✓ Regras salvas em /etc/iptables/rules.v4${NC}"

    # Criar serviço systemd para restaurar na inicialização
    cat > /etc/systemd/system/iptables-restore.service <<'EOF'
[Unit]
Description=Restore iptables rules
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Habilitar serviço
    systemctl daemon-reload
    systemctl enable iptables-restore.service
    echo -e "${GREEN}✓ Serviço systemd criado e habilitado${NC}"
else
    echo -e "${YELLOW}⚠ Não foi possível salvar regras automaticamente${NC}"
    echo -e "${YELLOW}⚠ A regra será perdida após reboot${NC}"
    echo ""
    echo -e "${YELLOW}Para tornar persistente manualmente, execute:${NC}"
    echo "  apt-get install iptables-persistent"
    echo "  netfilter-persistent save"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Testando conectividade SNMP...${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Testar SNMP se snmpwalk estiver disponível
if command -v snmpwalk &> /dev/null; then
    echo -e "${YELLOW}Testando SNMP do servidor...${NC}"
    if timeout 5 snmpwalk -v 2c -c Gwtelecom -O e $ROUTER_IP sysDescr 2>&1 | grep -q "SNMPv2-MIB"; then
        echo -e "${GREEN}✓ SNMP funcionando do servidor${NC}"
    else
        echo -e "${RED}✗ SNMP falhou do servidor${NC}"
    fi
else
    echo -e "${YELLOW}⚠ snmpwalk não instalado, pulando teste${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}Configuração concluída!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Próximos passos:${NC}"
echo "  1. git pull"
echo "  2. docker compose down akvorado-outlet"
echo "  3. docker compose up -d akvorado-outlet"
echo "  4. docker logs -f akvorado-outlet"
echo ""
echo -e "${YELLOW}Verificar se SNMP timeout desaparece e flows aparecem no ClickHouse${NC}"
echo ""
