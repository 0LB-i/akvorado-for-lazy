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
- **Kafka** (modo KRaft, sem Zookeeper): Message broker entre inlet e outlet

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
do banco de dados (ClickHouse) e sobe a stack completa.

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

Defina `CLICKHOUSE_USER` e `CLICKHOUSE_PASSWORD` (o ClickHouse é o único
serviço da stack que pede autenticação).

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
mkdir -p data/{clickhouse,kafka,geoip,console}
sudo chown -R 1000:1000 data/kafka data/console
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
./scripts/manage.sh update          # Atualizar imagens e reconstruir o Akvorado
```

## Portas Utilizadas

| Serviço | Porta | Protocolo | Acesso | Descrição |
|---------|-------|-----------|--------|-----------|
| Console Web | 8000 | TCP | Rede (`CONSOLE_BIND`) | Interface web |
| ClickHouse HTTP | 8123 | TCP | Rede (`CLICKHOUSE_BIND`) | API ClickHouse (Grafana, dashboard) |
| ClickHouse Native | 9000 | TCP | Rede (`CLICKHOUSE_BIND`) | Cliente ClickHouse (Grafana, SQL) |
| NetFlow | 2055 | UDP | Rede | Recepção NetFlow |
| sFlow | 6343 | UDP | Rede | Recepção sFlow |
| IPFIX | 4739 | UDP | Rede | Recepção IPFIX |
| Orchestrator HTTP | 8080 | TCP | Só localhost | API HTTP |
| Orchestrator gRPC | 8081 | TCP | Só localhost | API gRPC |
| Inlet HTTP | 8082 | TCP | Só localhost | API do coletor |
| Kafka | 9092 | TCP | Só localhost | Message broker |
| Kafka (host) | 9093 | TCP | Só localhost | Message broker (usado pelo inlet) |

Kafka, Orchestrator e a API do inlet não têm autenticação, então só escutam
em `127.0.0.1`. Para consultá-los de outra máquina, use um túnel SSH, ex.:
`ssh -L 8080:127.0.0.1:8080 usuario@servidor`.

ClickHouse e Console ficam abertos para a rede por padrão. Para fechá-los,
defina `CLICKHOUSE_BIND=127.0.0.1` e/ou `CONSOLE_BIND=127.0.0.1` no `.env`
e rode `docker compose up -d`. **O Docker ignora o firewalld/UFW para portas
publicadas**; para limitar por IP, use a chain `DOCKER-USER` (exemplo no
[PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md#firewall)).

## Estrutura de Diretórios

```
akvorado-for-lazy/
├── config/                              # Arquivos de configuração
│   ├── akvorado-orchestrator.yaml.example  # Template (gera akvorado-orchestrator.yaml)
│   ├── akvorado-inlet.yaml
│   └── clickhouse/                      # Configs customizadas ClickHouse
├── data/                     # Dados persistentes (não versionado)
│   ├── clickhouse/          # Dados do ClickHouse
│   ├── kafka/               # Dados do Kafka
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
```

O `config/akvorado-orchestrator.yaml` guarda uma cópia da senha e só é gerado
quando não existe. A forma mais simples de trocar a senha é rodar de novo
`sudo bash bootstrap.sh`, que atualiza o `.env` e regenera esse arquivo.

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
curl http://localhost:8000/api/v0/healthcheck
curl http://localhost:8080/api/v0/healthcheck
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
Kafka como `127.0.0.1:9093` (listener `PLAINTEXT_HOST`), não como
`kafka:9092` (o nome usado pelos outros serviços dentro da rede Docker). Se
o inlet ficar preso tentando `kafka:9092` — geralmente depois de mudar
`KAFKA_ADVERTISED_LISTENERS` ou trocar a config do inlet — force a
recriação do container para ele pegar a config atual:

```bash
docker compose up -d --force-recreate akvorado-inlet
docker compose logs -f akvorado-inlet
```

Confirme nos logs que a conexão está usando `127.0.0.1:9093`, não
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
# Via script (baixa imagens novas, reconstrói o Akvorado e reinicia)
git pull
./scripts/manage.sh update

# Manual
docker compose pull --ignore-pull-failures
docker compose build --pull
docker compose up -d --remove-orphans
```

### Atualizando instalações antigas (Redis/Zookeeper)

Versões anteriores deste projeto rodavam Redis (que o Akvorado não usava) e
Kafka em modo Zookeeper. Hoje o Kafka roda em modo KRaft (`apache/kafka`,
mesma imagem do compose oficial do Akvorado) e esses dois serviços saíram.

O `./scripts/manage.sh update` (ou o `install.sh`) faz a migração sozinho:

- move o `data/kafka` antigo, incompatível com o KRaft, para
  `data/kafka.zookeeper-backup-<data>` (só se perdem flows que ainda não
  tinham sido consumidos pelo outlet);
- remove os containers `akvorado-redis` e `akvorado-zookeeper`
  (`--remove-orphans`).

Rode com `sudo`, porque os diretórios em `data/` pertencem a root/uid 1000.
Depois que tudo estiver saudável, dá para apagar `data/redis`,
`data/zookeeper` e `data/kafka.zookeeper-backup-*`. As variáveis
`REDIS_*` e `ZOOKEEPER_PORT` que sobrarem no `.env` são ignoradas.

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
docker exec -it akvorado-kafka /opt/kafka/bin/kafka-console-consumer.sh \
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
