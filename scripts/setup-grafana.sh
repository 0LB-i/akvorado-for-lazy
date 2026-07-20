#!/bin/bash
# Script para instalar e configurar o Grafana no Akvorado

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "  Configuração do Grafana - Akvorado"
echo "=========================================="
echo ""

cd "$PROJECT_DIR"

# Verificar se o docker-compose.yml existe
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Erro: docker-compose.yml não encontrado"
    exit 1
fi

# Criar diretórios necessários
echo "📁 Criando diretórios..."
mkdir -p data/grafana
mkdir -p config/grafana/provisioning/datasources

# Verificar se o datasource já existe
if [ ! -f "config/grafana/provisioning/datasources/clickhouse.yaml" ]; then
    echo "❌ Erro: Arquivo de configuração do datasource não encontrado"
    echo "   Execute 'git pull' para obter os arquivos de configuração"
    exit 1
fi

# Verificar se o ClickHouse está rodando
echo "🔍 Verificando ClickHouse..."
if ! docker ps | grep -q akvorado-clickhouse; then
    echo "❌ Erro: ClickHouse não está rodando"
    echo "   Execute 'docker-compose up -d clickhouse' primeiro"
    exit 1
fi

# Iniciar Grafana
echo "🚀 Iniciando Grafana..."
docker-compose up -d grafana

# Aguardar o Grafana iniciar
echo "⏳ Aguardando Grafana iniciar..."
sleep 10

# Verificar se o Grafana está rodando
if docker ps | grep -q akvorado-grafana; then
    echo ""
    echo "✅ Grafana iniciado com sucesso!"
    echo ""
    echo "=========================================="
    echo "  Informações de Acesso"
    echo "=========================================="
    echo ""
    echo "URL: http://localhost:3000"
    echo "Usuário: admin"
    echo "Senha: admin"
    echo ""
    echo "⚠️  Altere a senha no primeiro acesso!"
    echo ""
    echo "📖 Consulte o arquivo GRAFANA.md para:"
    echo "   - Exemplos de queries"
    echo "   - Como criar dashboards"
    echo "   - Templates prontos"
    echo ""
    echo "O datasource 'Akvorado ClickHouse' já está"
    echo "pré-configurado e pronto para usar!"
    echo ""
else
    echo "❌ Erro ao iniciar Grafana"
    echo "Verifique os logs com: docker-compose logs grafana"
    exit 1
fi
