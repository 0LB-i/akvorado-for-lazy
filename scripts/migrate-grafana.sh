#!/bin/bash
# Script de Migração Automática do Grafana
# Migra dashboards, datasources e pastas de um Grafana para outro

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função de ajuda
show_help() {
    cat << EOF
Uso: $0 [opções]

Migra dashboards e configurações de um Grafana para outro.

Opções:
    -s, --source-url URL        URL do Grafana origem (ex: http://192.168.1.10:3000)
    -u, --source-user USER      Usuário admin do Grafana origem
    -p, --source-pass PASS      Senha do usuário admin do Grafana origem
    -t, --target-url URL        URL do Grafana destino (padrão: http://localhost:3000)
    -U, --target-user USER      Usuário admin do Grafana destino (padrão: admin)
    -P, --target-pass PASS      Senha do usuário admin do Grafana destino (padrão: admin)
    -d, --backup-dir DIR        Diretório para backup (padrão: /tmp/grafana-migration)
    -h, --help                  Mostra esta ajuda

Exemplos:
    # Migração básica
    $0 -s http://192.168.1.10:3000 -u admin -p senha123

    # Migração completa com customização
    $0 -s http://old-grafana:3000 -u admin -p old_pass \\
       -t http://new-grafana:3000 -U admin -P new_pass

    # Apenas exportar (sem importar)
    $0 -s http://192.168.1.10:3000 -u admin -p senha123 -d /backup/grafana

EOF
}

# Variáveis padrão
SOURCE_URL=""
SOURCE_USER=""
SOURCE_PASS=""
TARGET_URL="http://localhost:3000"
TARGET_USER="admin"
TARGET_PASS="admin"
BACKUP_DIR="/tmp/grafana-migration"

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--source-url)
            SOURCE_URL="$2"
            shift 2
            ;;
        -u|--source-user)
            SOURCE_USER="$2"
            shift 2
            ;;
        -p|--source-pass)
            SOURCE_PASS="$2"
            shift 2
            ;;
        -t|--target-url)
            TARGET_URL="$2"
            shift 2
            ;;
        -U|--target-user)
            TARGET_USER="$2"
            shift 2
            ;;
        -P|--target-pass)
            TARGET_PASS="$2"
            shift 2
            ;;
        -d|--backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Opção desconhecida: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

# Validação de parâmetros obrigatórios
if [ -z "$SOURCE_URL" ] || [ -z "$SOURCE_USER" ] || [ -z "$SOURCE_PASS" ]; then
    echo -e "${RED}❌ Erro: Parâmetros obrigatórios faltando${NC}"
    echo ""
    show_help
    exit 1
fi

# Criar diretório de backup
mkdir -p "$BACKUP_DIR"/{dashboards,datasources,folders}

echo "=========================================="
echo "  Migração de Grafana"
echo "=========================================="
echo ""
echo "Origem:  $SOURCE_URL"
echo "Destino: $TARGET_URL"
echo "Backup:  $BACKUP_DIR"
echo ""

# Função para verificar conectividade
check_connectivity() {
    local url=$1
    local user=$2
    local pass=$3

    if ! curl -s -f -u "$user:$pass" "$url/api/health" > /dev/null 2>&1; then
        echo -e "${RED}❌ Erro: Não foi possível conectar ao Grafana em $url${NC}"
        echo "   Verifique URL, usuário e senha"
        exit 1
    fi
}

# Verificar conectividade
echo "🔍 Verificando conectividade..."
check_connectivity "$SOURCE_URL" "$SOURCE_USER" "$SOURCE_PASS"
echo -e "${GREEN}✅ Grafana origem OK${NC}"

check_connectivity "$TARGET_URL" "$TARGET_USER" "$TARGET_PASS"
echo -e "${GREEN}✅ Grafana destino OK${NC}"
echo ""

# 1. Exportar pastas (folders)
echo "📁 Exportando pastas..."
folders=$(curl -s -u "$SOURCE_USER:$SOURCE_PASS" "$SOURCE_URL/api/folders")
echo "$folders" > "$BACKUP_DIR/folders/folders.json"
folder_count=$(echo "$folders" | jq '. | length')
echo -e "${GREEN}✅ $folder_count pastas exportadas${NC}"
echo ""

# 2. Importar pastas no destino
echo "📁 Importando pastas no destino..."
imported_folders=0
while IFS= read -r folder; do
    title=$(echo "$folder" | jq -r '.title')
    uid=$(echo "$folder" | jq -r '.uid')

    # Criar pasta no destino
    result=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$TARGET_USER:$TARGET_PASS" \
        -d "$folder" \
        "$TARGET_URL/api/folders" 2>&1)

    if echo "$result" | grep -q "name already exists\|uid already exists\|\"uid\":"; then
        echo "  ⚠️  Pasta já existe: $title"
    else
        echo "  ✅ Pasta criada: $title"
        ((imported_folders++))
    fi
done < <(echo "$folders" | jq -c '.[]')
echo -e "${GREEN}✅ $imported_folders novas pastas criadas${NC}"
echo ""

# 3. Exportar dashboards
echo "📊 Exportando dashboards..."
dashboards=$(curl -s -u "$SOURCE_USER:$SOURCE_PASS" "$SOURCE_URL/api/search?type=dash-db")
dashboard_count=$(echo "$dashboards" | jq '. | length')
echo -e "${YELLOW}📊 Total: $dashboard_count dashboards${NC}"
echo ""

# 4. Migrar cada dashboard
migrated=0
skipped=0
failed=0

while IFS= read -r dash; do
    uid=$(echo "$dash" | jq -r '.uid')
    title=$(echo "$dash" | jq -r '.title')
    folder=$(echo "$dash" | jq -r '.folderTitle // "General"')

    echo "📄 Migrando: $title (pasta: $folder)"

    # Exportar dashboard completo
    dashboard_json=$(curl -s -u "$SOURCE_USER:$SOURCE_PASS" \
        "$SOURCE_URL/api/dashboards/uid/$uid")

    # Salvar backup
    echo "$dashboard_json" > "$BACKUP_DIR/dashboards/$uid.json"

    # Preparar para importação (remover id e version)
    import_payload=$(echo "$dashboard_json" | jq '{
        dashboard: (.dashboard | del(.id, .version)),
        overwrite: true,
        folderId: .meta.folderId
    }')

    # Importar no destino
    result=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -u "$TARGET_USER:$TARGET_PASS" \
        -d "$import_payload" \
        "$TARGET_URL/api/dashboards/db")

    # Verificar resultado
    if echo "$result" | grep -q '"status":"success"'; then
        echo -e "  ${GREEN}✅ Migrado com sucesso${NC}"
        ((migrated++))
    elif echo "$result" | grep -q "name already exists\|version-mismatch"; then
        echo -e "  ${YELLOW}⚠️  Dashboard já existe (pulando)${NC}"
        ((skipped++))
    else
        echo -e "  ${RED}❌ Falha na migração${NC}"
        echo "$result" | jq '.message' 2>/dev/null || echo "$result"
        ((failed++))
    fi
    echo ""

done < <(echo "$dashboards" | jq -c '.[]')

# 5. Exportar datasources (apenas para backup)
echo "💾 Exportando datasources (backup)..."
datasources=$(curl -s -u "$SOURCE_USER:$SOURCE_PASS" "$SOURCE_URL/api/datasources")
echo "$datasources" > "$BACKUP_DIR/datasources/datasources.json"
datasource_count=$(echo "$datasources" | jq '. | length')
echo -e "${GREEN}✅ $datasource_count datasources exportados${NC}"
echo ""

# Resumo
echo "=========================================="
echo "  Resumo da Migração"
echo "=========================================="
echo ""
echo "📊 Dashboards:"
echo "   ✅ Migrados: $migrated"
echo "   ⚠️  Pulados: $skipped"
echo "   ❌ Falhados: $failed"
echo ""
echo "📁 Pastas: $imported_folders criadas"
echo "💾 Datasources: $datasource_count exportados (backup)"
echo ""
echo "📂 Backup salvo em: $BACKUP_DIR"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}🎉 Migração concluída com sucesso!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Migração concluída com algumas falhas${NC}"
    echo "   Verifique os logs acima para detalhes"
    exit 1
fi
