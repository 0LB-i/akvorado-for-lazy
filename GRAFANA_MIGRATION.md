# Guia de Migração - Grafana

Este guia explica como migrar dados de outro Grafana para o Grafana do Akvorado.

## O que pode ser migrado?

- ✅ Dashboards
- ✅ Datasources (fontes de dados)
- ✅ Pastas (folders)
- ✅ Alertas e notificações
- ✅ Usuários e permissões
- ✅ Configurações da organização
- ✅ Playlists
- ✅ Snapshots

## Métodos de Migração

### Método 1: Via API (Recomendado - Mais Simples)

**O que preciso:**
- URL do Grafana antigo (ex: `http://IP:3000`)
- Token de API ou usuário/senha admin do Grafana antigo

**Vantagens:**
- Não precisa acesso SSH ao servidor antigo
- Migração seletiva (escolhe o que copiar)
- Seguro e reversível

**Desvantagens:**
- Não migra usuários e senhas (apenas dashboards e configurações)

---

### Método 2: Cópia do Banco de Dados (Migração Completa)

**O que preciso:**
- Acesso SSH ao servidor do Grafana antigo
- Localização do arquivo `grafana.db` (SQLite)
  - Geralmente em `/var/lib/grafana/grafana.db`
  - Ou em Docker: volume `grafana-data`

**Vantagens:**
- Migração 100% completa (tudo é copiado)
- Inclui usuários, senhas, permissões, histórico

**Desvantagens:**
- Precisa parar o Grafana antigo durante a cópia
- Substitui tudo no Grafana novo
- Mais arriscado

---

### Método 3: Exportação Manual via UI

**O que preciso:**
- Acesso à interface web do Grafana antigo

**Vantagens:**
- Não precisa credenciais especiais
- Controle total sobre o que é migrado

**Desvantagens:**
- Trabalhoso para muitos dashboards
- Manual e demorado

---

## Instruções Detalhadas

### MÉTODO 1A: Migração via API com Script Automatizado

**Passo 1:** Forneça as informações do Grafana antigo:
```
URL: http://IP_ANTIGO:3000
Admin User: admin
Admin Password: senha_admin
```

**Passo 2:** Eu crio e executo um script que:
- Exporta todos os dashboards do Grafana antigo
- Importa automaticamente no Grafana novo
- Preserva pastas e estrutura

**Exemplo de comando:**
```bash
# Executado no servidor do Akvorado
./scripts/migrate-grafana.sh \
  --source-url http://IP_ANTIGO:3000 \
  --source-user admin \
  --source-pass senha_admin \
  --target-url http://localhost:3000 \
  --target-user admin \
  --target-pass admin
```

---

### MÉTODO 1B: Migração via API Manual

Se preferir fazer manualmente:

**1. Criar token de API no Grafana antigo:**
```
Configurações → API Keys → Add API key
- Nome: migration
- Role: Admin
- Copiar o token gerado
```

**2. Exportar dashboards:**
```bash
# Listar todos os dashboards
curl -H "Authorization: Bearer SEU_TOKEN_AQUI" \
  http://IP_ANTIGO:3000/api/search?type=dash-db

# Exportar dashboard específico (substituir DASHBOARD_UID)
curl -H "Authorization: Bearer SEU_TOKEN_AQUI" \
  http://IP_ANTIGO:3000/api/dashboards/uid/DASHBOARD_UID \
  -o dashboard.json
```

**3. Importar no Grafana novo:**
```bash
# Importar dashboard
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @dashboard.json \
  http://170.244.221.231:3000/api/dashboards/db
```

---

### MÉTODO 2: Migração Completa (Banco de Dados)

**Passo 1:** No servidor do Grafana ANTIGO:

```bash
# Parar o Grafana (se Docker)
docker-compose stop grafana

# Localizar o banco de dados
# Se Docker:
docker volume inspect grafana-data
# Geralmente em: /var/lib/docker/volumes/grafana-data/_data/grafana.db

# Se instalação nativa:
ls -la /var/lib/grafana/grafana.db

# Copiar o arquivo
cp /caminho/para/grafana.db /tmp/grafana-backup.db
```

**Passo 2:** Transferir para o servidor do Akvorado:

```bash
# Do servidor antigo para o novo
scp /tmp/grafana-backup.db root@170.244.221.231:/tmp/
```

**Passo 3:** No servidor do Akvorado:

```bash
cd /root/Akvorado

# Parar o Grafana
docker-compose stop grafana

# Substituir o banco de dados
docker cp /tmp/grafana-backup.db akvorado-grafana:/var/lib/grafana/grafana.db

# Ajustar permissões
docker exec -u root akvorado-grafana chown 472:472 /var/lib/grafana/grafana.db

# Reiniciar
docker-compose start grafana
```

**⚠️ ATENÇÃO:** Este método substitui TODO o conteúdo do Grafana novo!

---

### MÉTODO 3: Exportação Manual via Interface

**Passo 1:** No Grafana antigo:

1. Abrir cada dashboard
2. Clicar no ícone de **engrenagem** (⚙️) → **JSON Model**
3. Copiar todo o JSON
4. Salvar em um arquivo `.json`

**Passo 2:** No Grafana novo (http://170.244.221.231:3000):

1. Menu lateral → **+ (Create)** → **Import**
2. Colar o JSON ou fazer upload do arquivo
3. Selecionar o datasource: **Akvorado ClickHouse**
4. Clicar em **Import**

---

## Ferramenta Recomendada: grafana-backup

Existe uma ferramenta Python chamada `grafana-backup` que facilita muito:

**Instalação:**
```bash
pip install grafana-backup
```

**Configuração (`~/.grafana-backup.json`):**
```json
{
  "general": {
    "debug": true,
    "backup_dir": "/tmp/grafana-backups"
  },
  "grafana": {
    "url": "http://IP_ANTIGO:3000",
    "token": "SEU_TOKEN_AQUI"
  }
}
```

**Uso:**
```bash
# Backup do Grafana antigo
grafana-backup save

# Restaurar no Grafana novo
# (editar configuração para apontar para IP novo)
grafana-backup restore _OUTPUT_/2024-01-05T12-00-00.tar.gz
```

---

## Script Automatizado de Migração

Posso criar um script que automatiza todo o processo. Vou precisar apenas:

**Opção A - Via API (Recomendado):**
```
✅ URL do Grafana antigo
✅ Usuário admin do Grafana antigo
✅ Senha admin do Grafana antigo
```

**Opção B - Via Banco de Dados:**
```
✅ Acesso SSH ao servidor do Grafana antigo
✅ Usuário SSH
✅ Senha/chave SSH
✅ Localização do arquivo grafana.db
```

---

## Migração de Datasources

Se o Grafana antigo tem datasources específicos que você quer manter:

**Exportar datasource:**
```bash
# Listar datasources
curl -u admin:senha http://IP_ANTIGO:3000/api/datasources

# Exportar datasource específico
curl -u admin:senha http://IP_ANTIGO:3000/api/datasources/ID > datasource.json
```

**Importar no Grafana novo:**
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @datasource.json \
  http://170.244.221.231:3000/api/datasources
```

**Nota:** O datasource do ClickHouse já está configurado automaticamente no Grafana do Akvorado.

---

## Checklist Pós-Migração

Após a migração, verifique:

- [ ] Todos os dashboards foram importados
- [ ] Datasources estão funcionando
- [ ] Queries retornam dados corretamente
- [ ] Variáveis de template funcionam
- [ ] Alertas estão ativos (se aplicável)
- [ ] Permissões de usuários estão corretas
- [ ] Pastas e organização mantidas

---

## Ajuste de Datasources nos Dashboards

Se os dashboards do Grafana antigo usavam datasources diferentes, você precisará atualizar:

**Via UI:**
1. Abrir o dashboard
2. **Edit** → **Settings** → **JSON Model**
3. Buscar por `"datasource"` e substituir pelo novo nome: `"Akvorado ClickHouse"`
4. **Save dashboard**

**Via Script:**
```bash
# Script para atualizar datasource em todos os dashboards
# Eu posso criar isso se necessário
```

---

## Comparação dos Métodos

| Método | Complexidade | Tempo | Requer SSH? | Migra Usuários? | Risco |
|--------|--------------|-------|-------------|-----------------|-------|
| API Manual | Média | Alto | Não | Não | Baixo |
| API Automatizado | Baixa | Baixo | Não | Não | Baixo |
| Banco de Dados | Média | Médio | Sim (ambos) | Sim | Médio |
| Interface Manual | Baixa | Muito Alto | Não | Não | Baixo |
| grafana-backup | Baixa | Baixo | Não | Depende | Baixo |

---

## O que você prefere?

**Recomendação:** Método 1A (API Automatizado)

Me forneça:
1. URL do Grafana antigo: `http://_______________:3000`
2. Usuário admin: `_______________`
3. Senha admin: `_______________`

E eu crio um script que migra tudo automaticamente! 🚀

---

## Exemplo de Migração Completa

```bash
#!/bin/bash
# Script de migração automática
# Uso: ./migrate.sh

SOURCE_URL="http://GRAFANA_ANTIGO:3000"
SOURCE_USER="admin"
SOURCE_PASS="senha_antiga"

TARGET_URL="http://170.244.221.231:3000"
TARGET_USER="admin"
TARGET_PASS="admin"

# 1. Exportar lista de dashboards
echo "📥 Exportando dashboards do Grafana antigo..."
dashboards=$(curl -s -u $SOURCE_USER:$SOURCE_PASS \
  "$SOURCE_URL/api/search?type=dash-db" | jq -r '.[] | .uid')

# 2. Para cada dashboard
for uid in $dashboards; do
  echo "📄 Migrando dashboard: $uid"

  # Exportar
  dashboard=$(curl -s -u $SOURCE_USER:$SOURCE_PASS \
    "$SOURCE_URL/api/dashboards/uid/$uid")

  # Preparar para importação
  echo "$dashboard" | jq '.dashboard | {dashboard: ., overwrite: true}' > /tmp/dash.json

  # Importar
  curl -X POST \
    -H "Content-Type: application/json" \
    -u $TARGET_USER:$TARGET_PASS \
    -d @/tmp/dash.json \
    "$TARGET_URL/api/dashboards/db"

  echo "✅ Dashboard $uid migrado!"
done

echo "🎉 Migração concluída!"
```

Quer que eu crie este script personalizado para você?
