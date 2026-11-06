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
- Ajuste `workers:` por listener em `config/akvorado-inlet.yaml`
- Reduza retenção de dados (`resolutions:` em `config/akvorado-orchestrator.yaml`)

## Segurança

⚠️ **IMPORTANTE**: Antes de usar em produção:

1. Mude as senhas no arquivo `.env`:
```bash
nano .env
# Altere: CLICKHOUSE_PASSWORD
```

2. O Console não tem login local — ele confia em headers HTTP de um proxy
   autenticador (Authelia, OAuth2 Proxy, Traefik Forward Auth, etc.). Sem
   esse proxy na frente, o Console fica sem autenticação; veja a seção
   "Habilitar Autenticação" do [README.md](README.md) antes de expor a porta.

3. Configure firewall para permitir apenas IPs confiáveis

## Próximos Passos

- Configure dispositivos de rede
- Ajuste retenção de dados (`resolutions:` em `config/akvorado-orchestrator.yaml`, veja o README)
- Configure alertas e notificações
- Configure backup automático

## Documentação Completa

Leia o [README.md](README.md) completo para informações detalhadas.

---

**Suporte**: https://github.com/akvorado/akvorado
