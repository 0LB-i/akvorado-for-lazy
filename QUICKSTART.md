# Guia de Início Rápido - Akvorado

## Instalação em 3 Passos

### 1. Clone o repositório
```bash
git clone <seu-repositorio>
cd akvorado
```

### 2. Execute a instalação
```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

### 3. Acesse a interface
Abra o navegador em: **http://localhost:8000**

## Configurar Dispositivos de Rede

Configure seus roteadores/switches para enviar flows:

**NetFlow:**
```
ip flow-export destination <IP_DO_SERVIDOR> 2055
ip flow-export version 9
```

**sFlow:**
```
sflow destination <IP_DO_SERVIDOR> 6343
```

**IPFIX:**
```
flow exporter AKVORADO
 destination <IP_DO_SERVIDOR>
 transport udp 4739
```

## Comandos Úteis

```bash
# Gerenciamento
./scripts/manage.sh status    # Ver status
./scripts/manage.sh logs      # Ver logs
./scripts/manage.sh stats     # Estatísticas
./scripts/manage.sh restart   # Reiniciar

# Docker Compose direto
docker-compose ps             # Status
docker-compose logs -f        # Logs
docker-compose restart        # Reiniciar
docker-compose down          # Parar tudo
```

## Portas Principais

- **8000** - Interface Web (Console)
- **8080** - API Orchestrator
- **8123** - ClickHouse HTTP
- **9092** - Kafka
- **2055** - NetFlow (UDP)
- **6343** - sFlow (UDP)
- **4739** - IPFIX (UDP)

## GeoIP (Opcional)

1. Crie conta: https://www.maxmind.com/en/geolite2/signup
2. Baixe: GeoLite2-ASN.mmdb, GeoLite2-Country.mmdb, GeoLite2-City.mmdb
3. Copie para: `data/geoip/`
4. Reinicie: `docker-compose restart`

## Troubleshooting

**Containers não iniciam:**
```bash
docker-compose logs
docker-compose down && docker-compose up -d
```

**Flows não aparecem:**
```bash
# Verificar recepção de pacotes
sudo tcpdump -i any port 2055 -n

# Verificar logs do inlet
docker-compose logs akvorado-inlet

# Verificar ClickHouse
docker exec akvorado-clickhouse clickhouse-client --query="SELECT count() FROM akvorado.flows"
```

**Performance lenta:**
- Aumente RAM/CPU
- Edite `WORKERS` no `.env`
- Reduza retenção de dados

## Segurança

⚠️ **IMPORTANTE**: Antes de usar em produção:

1. Mude as senhas no arquivo `.env`:
```bash
nano .env
# Altere: CLICKHOUSE_PASSWORD, REDIS_PASSWORD
```

2. Habilite autenticação no Console:
```bash
nano config/akvorado.yaml
# Configure authentication
```

3. Configure firewall para permitir apenas IPs confiáveis

## Próximos Passos

- Configure dispositivos de rede
- Ajuste retenção de dados em `config/akvorado.yaml`
- Configure alertas e notificações
- Integre com Grafana para dashboards
- Configure backup automático

## Documentação Completa

Leia o [README.md](README.md) completo para informações detalhadas.

---

**Suporte**: https://github.com/akvorado/akvorado
