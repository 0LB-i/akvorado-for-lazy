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

Para ter informações de geolocalização e ASN:

1. Crie uma conta gratuita no MaxMind: https://www.maxmind.com/en/geolite2/signup
2. Baixe os arquivos:
   - GeoLite2-ASN.mmdb
   - GeoLite2-Country.mmdb
   - GeoLite2-City.mmdb
3. Coloque em `data/geoip/`

```bash
mkdir -p data/geoip
# Copie os arquivos .mmdb para data/geoip/
```

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
│   ├── geoip/               # Bancos GeoIP
│   └── console/             # SQLite com filtros salvos na UI do Console
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

A retenção é controlada pela chave `resolutions` dentro de `clickhouse:` em
`config/akvorado-orchestrator.yaml` (gerado a partir de
`config/akvorado-orchestrator.yaml.example` na instalação).

```yaml
clickhouse:
  resolutions:
    - interval: 0
      ttl: 360h   # dados brutos (15 dias)
    - interval: 1m
      ttl: 168h   # agregado de 1 minuto (1 semana)
    - interval: 5m
      ttl: 2160h  # agregado de 5 minutos (3 meses)
    - interval: 1h
      ttl: 8760h  # agregado de 1 hora (1 ano)
```

`interval: 0` é a tabela de dados brutos (`flows`); `ttl: 0` mantém os dados
para sempre. Depois de alterar, reinicie o orchestrator (`docker compose
restart akvorado-orchestrator`).

### Performance

Não existem `WORKERS`/`FLOW_BUFFER_SIZE`/`MAX_FLOWS_PER_SECOND` no `.env` —
essas variáveis não são lidas por nenhum serviço. O paralelismo real é
configurado por listener em `flow.inputs`, em `config/akvorado-inlet.yaml`:

```yaml
flow:
  inputs:
    - type: udp
      decoder: netflow
      listen: :2055
      workers: 6            # ajuste conforme os núcleos disponíveis
      receive-buffer: 212992
```

O mesmo padrão (`workers`, `receive-buffer`) se repete nos listeners de
IPFIX e sFlow logo abaixo, no mesmo arquivo.

### Segurança

#### Alterar Senhas

Edite o arquivo `.env`:

```bash
CLICKHOUSE_PASSWORD=SuaSenhaSuperSegura123
REDIS_PASSWORD=OutraSenhaSegura456
```

#### Habilitar Autenticação

O console do Akvorado **não tem usuários/senha locais** — ele é stateless e
espera um proxy autenticador na frente dele, que injeta a identidade via
headers HTTP. Isso não vem configurado neste projeto por padrão.

A config do console não vem de um arquivo montado — ela é gerada inline no
próprio `docker-compose.yml`, dentro do serviço `akvorado-console` (bloco
`cat > /tmp/config.yaml <<EOF ... EOF`). Para habilitar, coloque um proxy
(Authelia, Keycloak, OAuth2 Proxy, Traefik Forward Auth, etc.) na frente do
console e adicione ao heredoc, no mesmo nível de `http:`/`clickhouse:`:

```yaml
auth:
  headers:
    login: Remote-User
    name: Remote-Name
    email: Remote-Email
```

Sem esse proxy configurado, o console fica acessível sem autenticação — por
isso o firewall (próxima seção) é o controle de acesso real neste setup.

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

### Inlet não conecta no Kafka

O `akvorado-inlet` roda em `network_mode: host` (precisa receber pacotes
NetFlow/sFlow/IPFIX direto na interface do servidor), então ele enxerga o
Kafka como `localhost:9093` (listener `PLAINTEXT_HOST`), não como
`kafka:9092` (o nome usado pelos outros serviços dentro da rede Docker). Se
o inlet ficar preso tentando `kafka:9092` — geralmente depois de mudar
`KAFKA_ADVERTISED_LISTENERS` ou trocar a config do inlet — force a
recriação do container para ele pegar a config atual:

```bash
docker compose up -d --force-recreate akvorado-inlet
docker compose logs -f akvorado-inlet
```

Confirme nos logs que a conexão está usando `localhost:9093`, não
`kafka:9092`.

### Comparar com a config oficial do Akvorado

Se uma seção do YAML parece não ter efeito ou você suspeita de divergência
de schema entre esta versão do Akvorado e os arquivos deste repositório,
`scripts/get-outlet-config.sh` baixa o `docker-compose-quickstart` oficial
mais recente do [upstream](https://github.com/akvorado/akvorado) num
diretório temporário, para comparação manual:

```bash
./scripts/get-outlet-config.sh
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

Os scripts, configurações e dashboard deste repositório são licenciados sob
[MIT](LICENSE). O Akvorado em si (buildado a partir do upstream, não
redistribuído aqui) tem sua própria licença — [AGPL-3.0](https://github.com/akvorado/akvorado/blob/main/LICENSE.txt).

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
