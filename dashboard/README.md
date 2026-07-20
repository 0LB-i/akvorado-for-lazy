# Dashboard Customizado - Akvorado

Dashboard HTML completo para visualização e análise de dados de tráfego de rede coletados pelo Akvorado.

## Características

### Visualizações Incluídas

1. **Tráfego em Tempo Real**
   - Flows ativos nos últimos 5 minutos
   - Bandwidth total
   - Pacotes por segundo
   - Atualização automática a cada 30 segundos

2. **Top Talkers**
   - Top 10 IPs com maior troca de tráfego
   - Detecção automática de tráfego suspeito
   - Informações detalhadas de bytes e pacotes

3. **Análise Geográfica**
   - Distribuição de tráfego por país
   - Bandeiras dos países
   - Percentual de tráfego por região

4. **Protocolos e Portas**
   - Gráfico de distribuição por protocolo
   - Top 10 portas mais utilizadas
   - Identificação de serviços

5. **Tráfego Suspeito**
   - Detecção de Port Scanning
   - Identificação de Data Exfiltration
   - Alertas de segurança em tempo real
   - Classificação por severidade

6. **Timeline de Tráfego**
   - Gráfico de tráfego nas últimas 24 horas
   - Visualização por hora
   - Tendências de uso

## Instalação

### 1. Copiar arquivos para o servidor

```bash
# No seu computador local
scp -r dashboard/ diogenes@170.244.221.231:/var/www/html/

# Ou criar diretório no servidor
ssh diogenes@170.244.221.231
mkdir -p /var/www/html/akvorado-dashboard
cd /var/www/html/akvorado-dashboard
```

### 2. Configurar servidor web (Nginx ou Apache)

#### Nginx

```nginx
server {
    listen 80;
    server_name seu-dominio.com;

    root /var/www/html/akvorado-dashboard;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # CORS para permitir acesso ao ClickHouse
    location /clickhouse/ {
        proxy_pass http://localhost:8123/;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
        add_header Access-Control-Allow-Headers 'Origin, Content-Type, Accept';
    }
}
```

#### Apache

```apache
<VirtualHost *:80>
    ServerName seu-dominio.com
    DocumentRoot /var/www/html/akvorado-dashboard

    <Directory /var/www/html/akvorado-dashboard>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # CORS
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Methods "GET, POST, OPTIONS"
    Header set Access-Control-Allow-Headers "Origin, Content-Type, Accept"
</VirtualHost>
```

### 3. Configurar CORS no ClickHouse (se necessário)

Edite `/etc/clickhouse-server/config.xml`:

```xml
<http_server_default_response>
    <content_type>text/html; charset=UTF-8</content_type>
    <headers>
        <header>
            <name>Access-Control-Allow-Origin</name>
            <value>*</value>
        </header>
    </headers>
</http_server_default_response>
```

## Uso

### Acessar o Dashboard

1. Abra o navegador e acesse: `http://seu-servidor/akvorado-dashboard/`
2. Configure as credenciais do ClickHouse:
   - Host: `170.244.221.231:8123`
   - Usuário: `akvorado`
   - Senha: `akvorado123`
3. Clique em "Salvar" para aplicar as configurações
4. O dashboard começará a carregar os dados automaticamente

### Atualização Manual

Clique no botão "Atualizar" no canto superior direito para forçar uma atualização dos dados.

### Atualização Automática

O dashboard atualiza automaticamente a cada 30 segundos. Para alterar este intervalo, edite `dashboard.js`:

```javascript
refreshInterval: 30000 // Tempo em milissegundos (30000 = 30 segundos)
```

## Queries SQL Úteis

O arquivo `queries.sql` contém dezenas de queries prontas para análise de dados, incluindo:

- Tráfego em tempo real
- Top talkers
- Análise geográfica
- Protocolos e portas
- Detecção de ameaças
- Estatísticas gerais
- Relatórios

### Executar Queries Manualmente

```bash
# Via linha de comando
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM flows"

# Via interface web do ClickHouse
# Acesse: http://170.244.221.231:8123/play
```

## Verificação de Serviços

Use o script `remote-check.sh` para verificar o status dos serviços:

```bash
# Executar todas as verificações
./scripts/remote-check.sh all

# Verificações individuais
./scripts/remote-check.sh containers  # Status dos containers
./scripts/remote-check.sh health      # Saúde dos serviços
./scripts/remote-check.sh logs        # Logs recentes
./scripts/remote-check.sh flows       # Estatísticas de flows
./scripts/remote-check.sh resources   # Uso de recursos
./scripts/remote-check.sh errors      # Erros críticos
```

## Personalização

### Adicionar Novos Painéis

1. Edite `index.html` para adicionar um novo card:

```html
<div class="card">
    <h2>Meu Novo Painel</h2>
    <div id="meu-painel">
        <p>Conteúdo aqui</p>
    </div>
</div>
```

2. Crie uma função em `dashboard.js`:

```javascript
async function updateMeuPainel() {
    const query = `
        SELECT ...
        FROM flows
        FORMAT JSON
    `;

    const data = await executeQuery(query);
    // Processar e exibir dados
}
```

3. Adicione ao `refreshAll()`:

```javascript
async function refreshAll() {
    await Promise.all([
        // ... outros painéis
        updateMeuPainel()
    ]);
}
```

### Alterar Cores e Estilo

Edite a seção `<style>` em `index.html` para personalizar:

- Cores do tema
- Tamanhos de fonte
- Layout dos cards
- Animações

### Configurar Detecção de Ameaças

Edite `dashboard.js`, função `updateSuspiciousTraffic()` para ajustar os limites:

```javascript
// Port Scan
if (row.connection_attempts > 500) // Ajuste o limite

// Data Exfiltration
if (row.total_bytes > 5000000000) // Ajuste o limite (5GB)
```

## Troubleshooting

### Dashboard não carrega dados

1. Verifique se o ClickHouse está rodando:
```bash
docker exec akvorado-clickhouse clickhouse-client --query="SELECT 1"
```

2. Verifique as credenciais no painel de configurações

3. Abra o Console do navegador (F12) para ver erros

4. Verifique se o CORS está configurado corretamente

### Erro de CORS

Se você ver erros de CORS no console:

1. Configure o CORS no ClickHouse (veja seção 3 da instalação)
2. Ou use um proxy reverso (Nginx/Apache)
3. Ou acesse o dashboard pelo mesmo domínio do ClickHouse

### Dados não aparecem

1. Verifique se há flows no banco:
```bash
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM akvorado.flows"
```

2. Se não houver flows, verifique se os dispositivos estão enviando dados:
```bash
tcpdump -i any port 2055 -n
```

### Performance lenta

1. Reduza o intervalo de tempo das queries (24h → 1h)
2. Aumente o intervalo de atualização automática (30s → 60s)
3. Reduza o número de itens nas tabelas (LIMIT 10 → LIMIT 5)

## Segurança

### Recomendações

1. **Use HTTPS**: Configure SSL/TLS no servidor web
2. **Autenticação**: Adicione autenticação básica ou OAuth
3. **Firewall**: Restrinja acesso ao dashboard por IP
4. **Senhas Fortes**: Use senhas fortes para ClickHouse
5. **Atualizações**: Mantenha todos os componentes atualizados

### Exemplo de Autenticação Básica (Nginx)

```nginx
location / {
    auth_basic "Akvorado Dashboard";
    auth_basic_user_file /etc/nginx/.htpasswd;
    try_files $uri $uri/ =404;
}
```

Criar arquivo de senhas:
```bash
htpasswd -c /etc/nginx/.htpasswd admin
```

## Suporte

- Documentação Akvorado: https://demo.akvorado.net/docs
- Issues: https://github.com/akvorado/akvorado/issues

## Licença

Este dashboard é fornecido como está, sem garantias.
