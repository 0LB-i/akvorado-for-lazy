# Guia Rápido - Dashboard Akvorado

Este guia mostra como usar o novo dashboard customizado e as ferramentas de verificação criadas para o Akvorado.

## O Que Foi Criado?

### 1. Dashboard HTML Completo (`dashboard/`)

Um dashboard web profissional com:

- **Tráfego em Tempo Real**: Flows ativos, bandwidth, pacotes/seg
- **Top Talkers**: IPs com maior tráfego
- **Análise Geográfica**: Distribuição por país com bandeiras
- **Protocolos e Portas**: Gráficos de distribuição
- **Detecção de Ameaças**: Análise automática de tráfego suspeito
- **Timeline**: Gráfico de tráfego nas últimas 24h
- **Atualização Automática**: Refresh a cada 30 segundos

### 2. Script de Verificação Remota (`scripts/remote-check.sh`)

Verifica o status dos serviços do Akvorado no servidor:

```bash
./scripts/remote-check.sh all         # Todas as verificações
./scripts/remote-check.sh containers  # Status dos containers
./scripts/remote-check.sh health      # Saúde dos serviços
./scripts/remote-check.sh logs        # Logs recentes
./scripts/remote-check.sh flows       # Estatísticas de flows
./scripts/remote-check.sh resources   # Uso de recursos
./scripts/remote-check.sh errors      # Erros críticos
```

### 3. Queries SQL Úteis (`dashboard/queries.sql`)

Mais de 50 queries prontas para análise:
- Tráfego em tempo real
- Top talkers e conversações
- Análise geográfica
- Detecção de Port Scanning
- Detecção de DDoS
- Detecção de Data Exfiltration
- Relatórios diários
- E muito mais!

### 4. Script de Deploy (`scripts/deploy-dashboard.sh`)

Deploy automático do dashboard no servidor.

## Como Usar

### Opção 1: Deploy Automático (Recomendado)

```bash
# 1. Torne o script executável
chmod +x scripts/deploy-dashboard.sh

# 2. Execute o deploy
./scripts/deploy-dashboard.sh

# 3. Acesse no navegador
# http://170.244.221.231/akvorado-dashboard/
```

### Opção 2: Deploy Manual

```bash
# 1. Copiar arquivos para o servidor
scp -r dashboard/ diogenes@170.244.221.231:/var/www/html/akvorado-dashboard/

# 2. Acessar o servidor
ssh diogenes@170.244.221.231

# 3. Configurar permissões
sudo chmod -R 755 /var/www/html/akvorado-dashboard
sudo chown -R www-data:www-data /var/www/html/akvorado-dashboard

# 4. Acessar no navegador
# http://170.244.221.231/akvorado-dashboard/
```

### Opção 3: Usar Localmente

```bash
# 1. Abrir o arquivo diretamente no navegador
open dashboard/index.html

# Ou iniciar um servidor HTTP local
cd dashboard
python3 -m http.server 8888

# Acessar: http://localhost:8888
```

## Configuração Inicial

1. **Abra o dashboard** no navegador

2. **Configure as credenciais** no painel de configurações:
   - Host: `170.244.221.231:8123`
   - Usuário: `akvorado`
   - Senha: `akvorado123`

3. **Clique em Salvar** e os dados começarão a carregar

## Verificar Serviços

### Verificação Rápida

```bash
./scripts/remote-check.sh health
```

### Verificação Completa

```bash
./scripts/remote-check.sh all
```

Exemplo de saída:
```
==========================================
  Akvorado - Verificação Remota
==========================================

[1/6] Verificando containers...
NAME                     STATUS    PORTS
akvorado-orchestrator    running   0.0.0.0:8080->8080/tcp
akvorado-inlet           running
akvorado-outlet          running
akvorado-console         running   0.0.0.0:8000->8000/tcp
clickhouse               running   0.0.0.0:8123->8123/tcp

[2/6] Verificando saúde dos serviços...
Orchestrator: OK
Console: OK
ClickHouse: 1

...
```

## Análise de Dados

### Via Dashboard

1. Acesse o dashboard
2. Navegue pelos painéis:
   - **Tráfego em Tempo Real**: Veja atividade atual
   - **Top Talkers**: Identifique maiores consumidores
   - **Tráfego Suspeito**: Verifique alertas de segurança
   - **Análise Geográfica**: Veja origem do tráfego

### Via SQL

Execute as queries do arquivo `dashboard/queries.sql`:

```bash
# Conectar ao ClickHouse
ssh diogenes@170.244.221.231
docker exec -it akvorado-clickhouse clickhouse-client

# Executar query
SELECT count() FROM flows WHERE TimeReceived > now() - INTERVAL 24 HOUR;

# Ou diretamente
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM flows"
```

### Exemplos de Queries Úteis

**Total de flows (24h):**
```sql
SELECT count() as total_flows, sum(Bytes) / (1024*1024*1024) as total_gb
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR;
```

**Top 10 IPs:**
```sql
SELECT SrcAddr, sum(Bytes) as bytes
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY SrcAddr
ORDER BY bytes DESC
LIMIT 10;
```

**Detecção de Port Scanning:**
```sql
SELECT SrcAddr, uniq(DstPort) as ports_scanned
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY SrcAddr
HAVING ports_scanned > 50
ORDER BY ports_scanned DESC;
```

## Alertas de Segurança

O dashboard detecta automaticamente:

### 🔴 Port Scanning
- Mais de 500 tentativas de conexão
- Escaneamento de múltiplas portas

### 🔴 Data Exfiltration
- Transferência > 5GB em 1 hora
- Tráfego anormal para IPs externos

### 🟡 Atividade Suspeita
- Tráfego fora do horário comercial
- Conexões para países de alto risco
- Uso de portas não autorizadas

### 🟢 Tráfego Normal
- Dentro dos padrões esperados

## Solução de Problemas

### Dashboard não carrega

```bash
# 1. Verificar se o ClickHouse está rodando
./scripts/remote-check.sh containers

# 2. Verificar logs
./scripts/remote-check.sh logs

# 3. Testar conexão
curl http://170.244.221.231:8123/
```

### Sem dados no dashboard

```bash
# 1. Verificar se há flows no banco
ssh diogenes@170.244.221.231
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM flows"

# 2. Verificar inlet
./scripts/remote-check.sh flows

# 3. Verificar se dispositivos estão enviando flows
tcpdump -i any port 2055 -n
```

### Erros nos logs

```bash
# Ver erros críticos
./scripts/remote-check.sh errors

# Ver logs completos
ssh diogenes@170.244.221.231
cd /path/to/akvorado
docker compose logs -f
```

## Manutenção

### Atualizar Dashboard

```bash
# Fazer alterações nos arquivos em dashboard/
# Depois executar novamente:
./scripts/deploy-dashboard.sh
```

### Backup de Dados

```bash
ssh diogenes@170.244.221.231
cd /path/to/akvorado
./scripts/manage.sh backup
```

### Limpeza de Dados Antigos

```sql
-- Limpar flows com mais de 30 dias
ALTER TABLE flows DELETE WHERE TimeReceived < now() - INTERVAL 30 DAY;
```

## Recursos Adicionais

### Arquivos Criados

```
akvorado/
├── dashboard/
│   ├── index.html           # Dashboard principal
│   ├── dashboard.js         # Lógica e queries
│   ├── queries.sql          # Queries SQL úteis
│   └── README.md            # Documentação detalhada
│
└── scripts/
    ├── remote-check.sh      # Verificação remota
    └── deploy-dashboard.sh  # Deploy automático
```

### Links Úteis

- **Dashboard**: http://170.244.221.231/akvorado-dashboard/
- **Console Akvorado**: http://170.244.221.231:8000
- **ClickHouse HTTP**: http://170.244.221.231:8123
- **Orchestrator API**: http://170.244.221.231:8080

### Portas dos Serviços

| Serviço           | Porta | URL                            |
|-------------------|-------|--------------------------------|
| Dashboard Custom  | 80    | http://IP/akvorado-dashboard/  |
| Console Akvorado  | 8000  | http://IP:8000                 |
| Orchestrator      | 8080  | http://IP:8080                 |
| ClickHouse HTTP   | 8123  | http://IP:8123                 |
| ClickHouse Native | 9000  | clickhouse://IP:9000           |

## Próximos Passos

1. **Deploy do Dashboard**
   ```bash
   ./scripts/deploy-dashboard.sh
   ```

2. **Verificar Serviços**
   ```bash
   ./scripts/remote-check.sh all
   ```

3. **Acessar Dashboard**
   - Abra: http://170.244.221.231/akvorado-dashboard/
   - Configure credenciais
   - Explore os dados!

4. **Configurar Alertas** (opcional)
   - Ajuste limites de detecção em `dashboard.js`
   - Configure notificações por email/Slack

5. **Personalizar** (opcional)
   - Edite `dashboard/index.html` para customizar visual
   - Adicione novos painéis em `dashboard.js`
   - Crie novas queries em `queries.sql`

## Suporte

Para dúvidas ou problemas:

1. Consulte `dashboard/README.md` para documentação detalhada
2. Verifique logs com `./scripts/remote-check.sh logs`
3. Teste queries em `dashboard/queries.sql`

---

**Desenvolvido para facilitar a análise de tráfego de rede com Akvorado**
