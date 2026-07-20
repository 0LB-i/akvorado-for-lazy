# Akvorado - Network Flow Analyzer

Projeto completo para instalação e configuração do Akvorado em ambiente de produção usando Docker Compose.

## O que é o Akvorado?

Akvorado é uma ferramenta moderna de análise de fluxos de rede (NetFlow/sFlow/IPFIX) que oferece:

- Coleta de flows de múltiplos protocolos (NetFlow v5/v9, sFlow, IPFIX)
- Armazenamento eficiente em ClickHouse
- Interface web intuitiva para visualização
- Enriquecimento de dados com GeoIP e ASN
- Exportação para Kafka
- Alta performance e escalabilidade

## Arquitetura

Este projeto implementa a stack completa do Akvorado:

```
┌─────────────────────────────────────────────────┐
│  Dispositivos de Rede (Routers/Switches)       │
│  Enviam flows via NetFlow/sFlow/IPFIX          │
└─────────────────────┬───────────────────────────┘
                      │ UDP 2055/6343/4739
                      ▼
┌─────────────────────────────────────────────────┐
│  Akvorado Inlet (Coletor)                      │
│  - Recebe e processa flows                     │
│  - Normaliza dados                             │
└─────────────────────┬───────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│  Akvorado Orchestrator                         │
│  - Orquestração                                │
│  - Schema management                           │
│  - Enriquecimento (GeoIP, ASN)                │
└─────────┬──────────────────────┬────────────────┘
          │                      │
          ▼                      ▼
┌──────────────────┐   ┌──────────────────┐
│  ClickHouse      │   │  Kafka           │
│  Armazena flows  │   │  Exporta dados   │
└──────────┬───────┘   └──────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────┐
│  Akvorado Console (Web UI)                     │
│  Interface de visualização e análise           │
│  http://localhost:8000                         │
└─────────────────────────────────────────────────┘
```

## Componentes

- **Akvorado Inlet**: Coletor de flows
- **Akvorado Orchestrator**: Orquestrador e gerenciador
- **Akvorado Console**: Interface web
- **ClickHouse**: Banco de dados para armazenamento de flows
- **Redis**: Cache e armazenamento temporário
- **Kafka + Zookeeper**: Message broker para exportação

## Requisitos

### Hardware Mínimo (Ambiente de Teste)
- CPU: 4 cores
- RAM: 8 GB
- Disco: 50 GB SSD

### Hardware Recomendado (Produção)
- CPU: 8+ cores
- RAM: 16+ GB
- Disco: 500+ GB SSD (dependendo do volume de flows)

### Software
- Docker Engine 20.10+
- Docker Compose 2.0+ (ou docker-compose 1.29+)
- Sistema Operacional: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)

## Instalação em uma VM nova (Rocky Linux 9)

Para uma VM Rocky Linux 9 zerada, use o script `bootstrap.sh`: ele instala o
Docker, clona este repositório em `/opt/akvorado`, pergunta o usuário/senha
do banco de dados (usado em todos os serviços que exigem autenticação:
ClickHouse e Redis) e sobe a stack completa.

```bash
curl -fsSL https://raw.githubusercontent.com/0LB-i/akvorado-for-lazy/main/bootstrap.sh -o bootstrap.sh
sudo bash bootstrap.sh
```

Se preferir gerar a senha automaticamente, basta deixar o prompt de senha em
branco. Depois disso, pule direto para a seção [Acesse as interfaces web](#5-acesse-as-interfaces-web).

## Instalação Rápida

### 1. Clone o repositório

```bash
git clone https://github.com/0LB-i/akvorado-for-lazy.git
cd akvorado-for-lazy
```

### 2. Configure as variáveis de ambiente

```bash
cp .env.example .env
nano .env
```

Defina `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD` e `REDIS_PASSWORD` (use a
mesma senha nas duas, é o mesmo usuário/senha único usado em todos os
serviços que pedem autenticação).

**IMPORTANTE**: Mude as senhas padrão antes de usar em produção!

### 3. (Opcional) Configure GeoIP

Para ter informações de geolocalização e ASN, crie uma conta gratuita e
gere uma license key em https://www.maxmind.com/en/geolite2/signup - o
script de instalação (próximo passo) pergunta a key e baixa os bancos
GeoLite2 automaticamente. Detalhes e alternativas em [GEOIP_SETUP.md](GEOIP_SETUP.md).

### 4. Execute a instalação

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

O script irá:
- Verificar dependências
- Verificar portas disponíveis
- Criar diretórios necessários
- Baixar imagens Docker
- Iniciar todos os serviços
- Verificar saúde dos serviços

### 5. Acesse as interfaces web

Abra o navegador em:
- **Console Akvorado**: http://localhost:8000

## Instalação Manual

Se preferir instalar manualmente:

```bash
# 1. Criar diretórios
mkdir -p data/{clickhouse,redis,kafka,zookeeper,geoip}
mkdir -p logs
mkdir -p config

# 2. Configurar .env (se necessário)
cp .env.example .env
nano .env

# 3. Iniciar serviços
docker-compose up -d

# 4. Verificar status
docker-compose ps

# 5. Ver logs
docker-compose logs -f
```

## Configuração de Dispositivos de Rede

Configure seus roteadores/switches para enviar flows para o servidor:

### NetFlow v5/v9
```
ip flow-export destination <IP_DO_SERVIDOR> 2055
ip flow-export version 9
```

### sFlow
```
sflow destination <IP_DO_SERVIDOR> 6343
sflow agent-ip <IP_DO_DISPOSITIVO>
```

### IPFIX
```
flow exporter AKVORADO
 destination <IP_DO_SERVIDOR>
 transport udp 4739
```

## Gerenciamento

Use o script de gerenciamento para operações comuns:

```bash
chmod +x scripts/manage.sh

# Ver comandos disponíveis
./scripts/manage.sh help

# Comandos úteis
./scripts/manage.sh status          # Status dos containers
./scripts/manage.sh logs            # Ver logs
./scripts/manage.sh stats           # Estatísticas de flows
./scripts/manage.sh health          # Verificar saúde
./scripts/manage.sh restart         # Reiniciar serviços
./scripts/manage.sh backup          # Backup dos dados
./scripts/manage.sh update          # Atualizar imagens
```

## Portas Utilizadas

| Serviço | Porta | Protocolo | Descrição |
|---------|-------|-----------|-----------|
| Console Web | 8000 | TCP | Interface web |
| Orchestrator HTTP | 8080 | TCP | API HTTP |
| Orchestrator gRPC | 8081 | TCP | API gRPC |
| Inlet HTTP | 8082 | TCP | API do coletor |
| ClickHouse HTTP | 8123 | TCP | API ClickHouse |
| ClickHouse Native | 9000 | TCP | Cliente ClickHouse |
| Redis | 6379 | TCP | Cache |
| Kafka | 9092 | TCP | Message broker |
| Zookeeper | 2181 | TCP | Coordenação Kafka |
| NetFlow | 2055 | UDP | Recepção NetFlow |
| sFlow | 6343 | UDP | Recepção sFlow |
| IPFIX | 4739 | UDP | Recepção IPFIX |

## Estrutura de Diretórios

```
akvorado-for-lazy/
├── config/                              # Arquivos de configuração
│   ├── akvorado-orchestrator.yaml.example  # Template (gera akvorado-orchestrator.yaml)
│   ├── akvorado-inlet.yaml
│   └── clickhouse/                      # Configs customizadas ClickHouse
├── data/                     # Dados persistentes (não versionado)
│   ├── clickhouse/          # Dados do ClickHouse
│   ├── redis/               # Dados do Redis
│   ├── kafka/               # Dados do Kafka
│   ├── zookeeper/           # Dados do Zookeeper
│   └── geoip/               # Bancos GeoIP
├── logs/                    # Logs da aplicação (não versionado)
├── scripts/                 # Scripts de automação
│   ├── install.sh          # Script de instalação (roda na VM já clonada)
│   └── manage.sh           # Script de gerenciamento
├── bootstrap.sh            # Instala dependências + clona + instala (VM nova)
├── docker-compose.yml      # Definição dos serviços
├── .env                    # Variáveis de ambiente (gerado, não versionado)
├── .env.example           # Exemplo de .env
└── README.md              # Este arquivo
```

## Configurações Importantes

### Retenção de Dados

Por padrão, os dados são retidos por:
- Flows detalhados: 7 dias
- Dados agregados: 90 dias

Para alterar, edite `config/akvorado.yaml`:

```yaml
clickhouse:
  retention:
    flows: 168h      # 7 dias (ajuste conforme necessário)
    aggregated: 2160h # 90 dias (ajuste conforme necessário)
```

### Performance

Para ajustar performance, edite `.env`:

```bash
# Número de workers
WORKERS=4

# Buffer de flows
FLOW_BUFFER_SIZE=100000

# Rate limit
MAX_FLOWS_PER_SECOND=100000
```

### Segurança

#### Alterar Senhas

Edite o arquivo `.env`:

```bash
CLICKHOUSE_PASSWORD=SuaSenhaSuperSegura123
REDIS_PASSWORD=OutraSenhaSegura456
```

#### Habilitar Autenticação

Edite `config/akvorado.yaml`:

```yaml
console:
  authentication:
    enabled: true
    type: basic
    users:
      - username: admin
        password: $2y$10$... # Use bcrypt hash
```

Para gerar hash bcrypt:
```bash
htpasswd -bnBC 10 "" sua_senha | tr -d ':\n'
```

## Backup e Restauração

### Backup Automático

```bash
./scripts/manage.sh backup
```

Cria um backup em `backups/akvorado_backup_YYYYMMDD_HHMMSS.tar.gz`

### Restauração

```bash
./scripts/manage.sh restore
```

### Backup Manual

```bash
# Parar serviços
docker-compose stop

# Backup
tar -czf backup.tar.gz data/ config/ .env

# Reiniciar
docker-compose start
```

## Monitoramento

### Logs

```bash
# Todos os serviços
docker-compose logs -f

# Serviço específico
docker-compose logs -f akvorado-console
docker-compose logs -f akvorado-inlet
docker-compose logs -f clickhouse
```

### Métricas

O Akvorado expõe métricas Prometheus na porta 9090.

Para integrar com Prometheus, adicione ao `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'akvorado'
    static_configs:
      - targets: ['localhost:9090']
```

### Health Check

```bash
# Via script
./scripts/manage.sh health

# Manual
curl http://localhost:8000/health
curl http://localhost:8080/health
```

## Troubleshooting

### Containers não iniciam

```bash
# Verificar logs
docker-compose logs

# Verificar se portas estão em uso
netstat -tuln | grep -E '(8000|8080|2055|6343|4739)'

# Recriar containers
docker-compose down
docker-compose up -d
```

### Flows não aparecem

1. Verifique se os dispositivos estão enviando flows:
```bash
tcpdump -i any port 2055 -n
```

2. Verifique logs do inlet:
```bash
docker-compose logs akvorado-inlet
```

3. Verifique se os dados estão chegando no ClickHouse:
```bash
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM akvorado.flows"
```

### ClickHouse com problemas

```bash
# Verificar logs
docker-compose logs clickhouse

# Verificar saúde
docker exec akvorado-clickhouse clickhouse-client --query="SELECT 1"

# Reiniciar
docker-compose restart clickhouse
```

### Performance lenta

1. Aumente recursos (RAM, CPU)
2. Ajuste workers no `.env`
3. Otimize retenção de dados
4. Considere sharding do ClickHouse

## Atualização

```bash
# Via script
./scripts/manage.sh update

# Manual
docker-compose pull
docker-compose up -d
```

## Desinstalação

### Remover containers (manter dados)

```bash
docker-compose down
```

### Remover tudo (incluindo dados)

```bash
docker-compose down -v
rm -rf data/ logs/
```

## Integração com Kafka

Os flows são automaticamente exportados para Kafka no tópico `akvorado-flows`.

Para consumir os dados:

```bash
# Via kafka-console-consumer
docker exec -it akvorado-kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic akvorado-flows \
  --from-beginning
```

## Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature
3. Commit suas mudanças
4. Push para a branch
5. Abra um Pull Request

## Suporte

- Documentação oficial: https://demo.akvorado.net/docs
- GitHub: https://github.com/akvorado/akvorado
- Issues: https://github.com/akvorado/akvorado/issues

## Licença

Este projeto de instalação é fornecido como está. O Akvorado possui sua própria licença.

## Changelog

### v1.0.0 (2025)
- Instalação inicial completa
- Docker Compose para todos os componentes
- Suporte a GeoIP e ASN
- Exportação para Kafka
- Scripts de gerenciamento
- Configuração otimizada para produção

---

**Desenvolvido para facilitar a instalação do Akvorado em ambientes de produção.**
