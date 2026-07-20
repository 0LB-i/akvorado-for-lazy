#!/bin/bash

# Script para fazer deploy do dashboard no servidor remoto
# Uso: ./deploy-dashboard.sh

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurações
REMOTE_HOST="170.244.221.231"
REMOTE_USER="diogenes"
REMOTE_PASS="Bd121012%+"
DASHBOARD_DIR="/var/www/html/akvorado-dashboard"

echo -e "${BLUE}=========================================="
echo "  Deploy do Dashboard Akvorado"
echo -e "==========================================${NC}"
echo ""

# Verificar se o diretório dashboard existe localmente
if [ ! -d "dashboard" ]; then
    echo -e "${RED}Erro: Diretório 'dashboard' não encontrado!${NC}"
    echo "Execute este script a partir do diretório raiz do projeto."
    exit 1
fi

echo -e "${YELLOW}[1/5] Preparando arquivos...${NC}"
cd dashboard
echo -e "${GREEN}✓ Arquivos prontos${NC}"
echo ""

echo -e "${YELLOW}[2/5] Conectando ao servidor...${NC}"

# Função para executar comandos remotos
remote_exec() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "$1"
}

# Verificar conectividade
if ! remote_exec "echo 'Conexão estabelecida'"; then
    echo -e "${RED}Erro: Não foi possível conectar ao servidor${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Conectado ao servidor${NC}"
echo ""

echo -e "${YELLOW}[3/5] Criando diretório no servidor...${NC}"
remote_exec "mkdir -p $DASHBOARD_DIR"
echo -e "${GREEN}✓ Diretório criado${NC}"
echo ""

echo -e "${YELLOW}[4/5] Fazendo upload dos arquivos...${NC}"
sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no -r * "$REMOTE_USER@$REMOTE_HOST:$DASHBOARD_DIR/"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Arquivos enviados com sucesso${NC}"
else
    echo -e "${RED}Erro ao enviar arquivos${NC}"
    exit 1
fi

echo ""

echo -e "${YELLOW}[5/5] Configurando permissões...${NC}"
remote_exec "chmod -R 755 $DASHBOARD_DIR"
remote_exec "chown -R www-data:www-data $DASHBOARD_DIR 2>/dev/null || chown -R nginx:nginx $DASHBOARD_DIR 2>/dev/null || true"
echo -e "${GREEN}✓ Permissões configuradas${NC}"
echo ""

# Verificar se Nginx ou Apache está instalado
echo -e "${YELLOW}Verificando servidor web...${NC}"

if remote_exec "command -v nginx"; then
    WEB_SERVER="nginx"
    echo -e "${GREEN}✓ Nginx detectado${NC}"
elif remote_exec "command -v apache2 || command -v httpd"; then
    WEB_SERVER="apache"
    echo -e "${GREEN}✓ Apache detectado${NC}"
else
    WEB_SERVER="none"
    echo -e "${YELLOW}⚠ Nenhum servidor web detectado${NC}"
fi

echo ""

# Criar configuração do Nginx se necessário
if [ "$WEB_SERVER" = "nginx" ]; then
    echo -e "${YELLOW}Deseja criar a configuração do Nginx? (s/n)${NC}"
    read -r CREATE_NGINX

    if [ "$CREATE_NGINX" = "s" ] || [ "$CREATE_NGINX" = "S" ]; then
        echo "Digite o nome do domínio (ou pressione Enter para usar o IP):"
        read -r DOMAIN
        DOMAIN=${DOMAIN:-$REMOTE_HOST}

        cat > /tmp/akvorado-dashboard.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    root $DASHBOARD_DIR;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # CORS para ClickHouse
    location ~* \.(json)$ {
        add_header Access-Control-Allow-Origin * always;
        add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS' always;
        add_header Access-Control-Allow-Headers 'Origin, Content-Type, Accept' always;
    }

    # Logs
    access_log /var/log/nginx/akvorado-dashboard-access.log;
    error_log /var/log/nginx/akvorado-dashboard-error.log;
}
EOF

        sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no /tmp/akvorado-dashboard.conf "$REMOTE_USER@$REMOTE_HOST:/tmp/"
        remote_exec "sudo mv /tmp/akvorado-dashboard.conf /etc/nginx/sites-available/"
        remote_exec "sudo ln -sf /etc/nginx/sites-available/akvorado-dashboard.conf /etc/nginx/sites-enabled/"
        remote_exec "sudo nginx -t && sudo systemctl reload nginx"

        echo -e "${GREEN}✓ Configuração do Nginx criada e aplicada${NC}"
    fi
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Deploy Concluído com Sucesso!"
echo -e "==========================================${NC}"
echo ""
echo -e "Dashboard disponível em:"
echo -e "${BLUE}http://$REMOTE_HOST/akvorado-dashboard/${NC}"
echo ""
echo "Próximos passos:"
echo "1. Acesse o dashboard no navegador"
echo "2. Configure as credenciais do ClickHouse se necessário"
echo "3. Verifique se os dados estão sendo carregados"
echo ""
echo "Para verificar logs:"
echo "  ssh $REMOTE_USER@$REMOTE_HOST"
echo "  tail -f /var/log/nginx/akvorado-dashboard-error.log"
echo ""

cd ..
