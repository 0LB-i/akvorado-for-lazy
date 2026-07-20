# Grafana - Dashboards para Akvorado

## Instalação e Acesso

### 1. Iniciar o Grafana

No servidor, execute:

```bash
cd /root/Akvorado
docker-compose up -d grafana
```

### 2. Acessar o Grafana

Abra o navegador em: **http://170.244.221.231:3000**

**Credenciais padrão:**
- Usuário: `admin`
- Senha: `admin`

O Grafana irá pedir para alterar a senha no primeiro acesso.

### 3. Verificar Datasource

O datasource do ClickHouse já está pré-configurado:
- Nome: **Akvorado ClickHouse**
- Tipo: **ClickHouse**
- URL: `http://clickhouse:8123`
- Database: `akvorado`

Para verificar:
1. Menu lateral → **Configuration** → **Data sources**
2. Clique em **Akvorado ClickHouse**
3. Clique em **Save & test**

## Exemplos de Queries

### Query 1: Top Protocolos (últimas 24h)

```sql
SELECT
    Protocol,
    dictGet('akvorado.protocols', 'name', Protocol) AS protocol_name,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
GROUP BY Protocol
ORDER BY total_bytes DESC
LIMIT 10
```

### Query 2: Top ASNs de Origem (últimas 24h)

```sql
SELECT
    SrcAS,
    dictGet('akvorado.asns', 'name', SrcAS) AS asn_name,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size,
    count() AS flow_count
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
  AND SrcAS > 0
GROUP BY SrcAS
ORDER BY total_bytes DESC
LIMIT 10
```

### Query 3: Top Portas de Destino (últimas 24h)

```sql
SELECT
    DstPort,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size,
    count() AS flow_count
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
  AND DstPort > 0
GROUP BY DstPort
ORDER BY total_bytes DESC
LIMIT 10
```

### Query 4: Tráfego por País (últimas 24h)

```sql
SELECT
    DstCountry,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size,
    count() AS flow_count
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
  AND DstCountry != ''
GROUP BY DstCountry
ORDER BY total_bytes DESC
LIMIT 15
```

### Query 5: Time Series - Tráfego Total (Gbps)

```sql
SELECT
    toStartOfInterval(TimeReceived, INTERVAL 5 MINUTE) AS time,
    sum(Bytes * 8) / 1000000000 / 300 AS gbps
FROM akvorado.flows
WHERE $__timeFilter(TimeReceived)
GROUP BY time
ORDER BY time
```

**Nota:** Use esta query em um painel **Time series**. O Grafana automaticamente substitui `$__timeFilter()` pelo filtro de tempo selecionado.

### Query 6: Top IPs de Origem (últimas 24h)

```sql
SELECT
    SrcAddr,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size,
    count() AS flow_count
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
GROUP BY SrcAddr
ORDER BY total_bytes DESC
LIMIT 10
```

### Query 7: Análise de Ataques DDoS (últimas 24h)

```sql
SELECT
    DstAddr AS target_ip,
    count(DISTINCT SrcAddr) AS unique_sources,
    count() AS flow_count,
    sum(Packets) AS total_packets,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
GROUP BY target_ip
HAVING unique_sources > 100
ORDER BY unique_sources DESC
LIMIT 20
```

### Query 8: Tráfego por Interface (últimas 24h)

```sql
SELECT
    InIfName,
    sum(Bytes) AS total_bytes,
    formatReadableSize(total_bytes) AS readable_size,
    count() AS flow_count
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
  AND InIfName != ''
GROUP BY InIfName
ORDER BY total_bytes DESC
LIMIT 10
```

## Criando Dashboards

### Dashboard 1: Overview de Tráfego

1. Crie um novo dashboard: **+ → Dashboard**
2. Adicione os seguintes painéis:

**Painel 1: Tráfego Total (Time Series)**
- Visualization: Time series
- Query: Query 5 (Time Series)
- Unit: Gbps

**Painel 2: Top Protocolos (Bar Chart)**
- Visualization: Bar chart
- Query: Query 1
- Transformation: Organize fields (mostrar apenas protocol_name e readable_size)

**Painel 3: Top ASNs (Table)**
- Visualization: Table
- Query: Query 2

**Painel 4: Top Países (Pie Chart)**
- Visualization: Pie chart
- Query: Query 4

### Dashboard 2: Análise de Segurança

1. Crie um novo dashboard
2. Adicione os seguintes painéis:

**Painel 1: Possíveis DDoS Attacks (Table)**
- Visualization: Table
- Query: Query 7

**Painel 2: Top Portas Destino (Bar Chart)**
- Visualization: Bar chart
- Query: Query 3

**Painel 3: Top IPs de Origem (Table)**
- Visualization: Table
- Query: Query 6

## Variáveis de Dashboard

Para criar dashboards dinâmicos, você pode usar variáveis:

### Variável: Time Range

Já incluída automaticamente no Grafana.

### Variável: Protocol

1. Settings → Variables → Add variable
2. Name: `protocol`
3. Type: Query
4. Data source: Akvorado ClickHouse
5. Query:
```sql
SELECT DISTINCT Protocol
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
ORDER BY Protocol
```

### Variável: ASN

1. Settings → Variables → Add variable
2. Name: `asn`
3. Type: Query
4. Data source: Akvorado ClickHouse
5. Query:
```sql
SELECT DISTINCT SrcAS
FROM akvorado.flows
WHERE TimeReceived >= now() - INTERVAL 24 HOUR
  AND SrcAS > 0
ORDER BY SrcAS
```

## Dicas de Performance

1. **Use tabelas agregadas** para queries de longo período:
   - `akvorado.flows_1m0s` - Agregado por 1 minuto
   - `akvorado.flows_5m0s` - Agregado por 5 minutos
   - `akvorado.flows_1h0m0s` - Agregado por 1 hora

2. **Limite o período de tempo** nas queries para melhor performance

3. **Use índices** - O ClickHouse já otimiza automaticamente, mas sempre filtre por `TimeReceived`

4. **Cache de queries** - Configure no ClickHouse para queries repetidas

## Exemplo de Dashboard JSON

Você pode importar este dashboard básico:

```json
{
  "dashboard": {
    "title": "Akvorado - Network Overview",
    "panels": [
      {
        "title": "Total Traffic (Gbps)",
        "type": "timeseries",
        "targets": [
          {
            "rawSql": "SELECT toStartOfInterval(TimeReceived, INTERVAL 5 MINUTE) AS time, sum(Bytes * 8) / 1000000000 / 300 AS gbps FROM akvorado.flows WHERE $__timeFilter(TimeReceived) GROUP BY time ORDER BY time",
            "format": "time_series"
          }
        ]
      }
    ]
  }
}
```

## Alertas

Configure alertas no Grafana para monitorar anomalias:

1. **Alerta de Tráfego Alto**: Dispara quando tráfego > 5 Gbps
2. **Alerta de DDoS**: Dispara quando unique_sources > 1000 para um IP
3. **Alerta de Porta Anormal**: Dispara quando portas não-padrão têm alto tráfego

## Integração com Outros Sistemas

O Grafana pode exportar dados para:
- Slack
- Email
- Webhook
- PagerDuty
- Telegram

Configure em: **Alerting → Contact points**

## Suporte

- Documentação Grafana: https://grafana.com/docs/
- Plugin ClickHouse: https://grafana.com/grafana/plugins/grafana-clickhouse-datasource/
- Comunidade Grafana: https://community.grafana.com/
