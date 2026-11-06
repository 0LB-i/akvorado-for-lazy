# Checklist para Produção - Akvorado

Use este checklist antes de colocar o Akvorado em produção.

## Segurança

### Senhas e Credenciais

- [ ] Alterar senha do ClickHouse no `.env` (CLICKHOUSE_PASSWORD)
- [ ] Gerar senhas fortes (mínimo 16 caracteres)
- [ ] Armazenar credenciais em local seguro (vault/password manager)

### Autenticação

- [ ] O Console não tem usuários/senha locais — ele exige um proxy
      autenticador externo (Authelia, Keycloak, OAuth2 Proxy, Traefik
      Forward Auth) na frente, que injeta a identidade via headers HTTP
      (bloco `auth.headers`, adicionado ao heredoc de config do serviço
      `akvorado-console` no `docker-compose.yml` — esse serviço não monta
      nenhum arquivo de config, gera o próprio inline)
- [ ] Sem esse proxy, o Console fica sem autenticação nenhuma — garantir
      que o firewall (seção abaixo) restrinja o acesso à porta do Console
- [ ] Testar login através do proxy

### Firewall

Kafka (9092/9093), Orchestrator (8080/8081) e a API do inlet (8082) já
escutam só em `127.0.0.1` — não precisam de regra de firewall. Ficam abertos
para a rede apenas o Console (8000), o ClickHouse (8123/9000) e as portas UDP
de flows.

- [ ] Permitir apenas IPs autorizados no Console (8000) e no ClickHouse (8123, 9000)
- [ ] Se ninguém de fora acessa o banco (Grafana etc.), usar `CLICKHOUSE_BIND=127.0.0.1` no `.env`
- [ ] Permitir IPs dos dispositivos de rede nas portas de flow (2055, 6343, 4739)
- [ ] Usuário só-leitura no ClickHouse para Grafana/dashboard (não reutilizar o do orchestrator)
- [ ] Considerar VPN para acesso administrativo

**Atenção:** portas publicadas pelo Docker (Console e ClickHouse) **não passam
pelas regras do firewalld/UFW** — o Docker insere as próprias regras de NAT
antes delas. Para limitar por IP de origem, use a chain `DOCKER-USER`:

```bash
# Libera Console e ClickHouse só para a rede de gerência (ajuste a faixa)
for port in 8000 8123 9000; do
  iptables -I DOCKER-USER -p tcp -m conntrack --ctorigdstport "$port" --ctdir ORIGINAL ! -s 192.168.1.0/24 -j DROP
done
```

(Para persistir após reboot, salve com `iptables-save` como em
`scripts/setup-nat.sh`.)

As portas UDP de flows são recebidas pelo inlet direto no host
(`network_mode: host`), então essas sim respeitam o firewalld:

```bash
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.0.0.0/8 port port=2055 protocol=udp accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.0.0.0/8 port port=6343 protocol=udp accept'
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.0.0.0/8 port port=4739 protocol=udp accept'
firewall-cmd --reload
```

### SSL/TLS

- [ ] Configurar HTTPS para o Console (via reverse proxy)
- [ ] Obter certificado SSL válido (Let's Encrypt)
- [ ] Redirecionar HTTP para HTTPS
- [ ] Configurar HSTS

### Rede

- [ ] Servidor em rede segmentada (DMZ ou rede de gerenciamento)
- [ ] Acesso SSH apenas com chaves (desabilitar senha)
- [ ] Configurar fail2ban
- [ ] Desabilitar serviços desnecessários

## Performance

### Hardware

- [ ] CPU: Mínimo 8 cores para produção
- [ ] RAM: Mínimo 16 GB
- [ ] Disco: SSD com 500+ GB (ou mais dependendo do volume)
- [ ] Rede: Interface Gigabit ou superior

### Configuração

- [ ] Ajustar `workers`/`receive-buffer` de cada listener em
      `flow.inputs` (`config/akvorado-inlet.yaml`) — recomendado: workers
      próximo do número de CPUs disponíveis para o inlet
- [ ] Otimizar cache do ClickHouse

### Monitoramento de Recursos

- [ ] Configurar alertas de CPU > 80%
- [ ] Configurar alertas de RAM > 80%
- [ ] Configurar alertas de disco > 80%
- [ ] Monitorar I/O do disco

## Dados

### Retenção

- [ ] Definir política de retenção apropriada
- [ ] Configurar `resolutions` (lista de `interval`/`ttl`) em `clickhouse:`,
      dentro de `config/akvorado-orchestrator.yaml` — ver exemplo comentado
      em `config/akvorado-orchestrator.yaml.example`
- [ ] Calcular espaço em disco necessário
- [ ] Testar limpeza automática (TTL do ClickHouse)

### Backup

- [ ] Configurar backup automático diário
- [ ] Testar restauração de backup
- [ ] Armazenar backups em local separado
- [ ] Definir retenção de backups (ex: 30 dias)
- [ ] Documentar procedimento de recuperação

Exemplo cron para backup:
```bash
# Adicionar ao crontab
0 2 * * * cd /path/to/akvorado && ./scripts/manage.sh backup
```

### GeoIP

- [ ] Baixar e instalar bancos GeoIP2
- [ ] Configurar atualização automática (semanal)
- [ ] Verificar licença MaxMind configurada
- [ ] Testar enriquecimento de dados

## Alta Disponibilidade

### Docker

- [ ] Configurar restart policy: unless-stopped
- [ ] Testar reinício automático após falha
- [ ] Configurar healthchecks em todos os containers

### ClickHouse

- [ ] Considerar cluster ClickHouse para HA (ambientes críticos)
- [ ] Configurar replicação (se cluster)
- [ ] Testar failover

### Kafka

- [ ] Configurar múltiplos brokers (produção crítica)
- [ ] Configurar replication factor adequado
- [ ] Monitorar lag de consumidores

## Monitoramento

### Métricas

- [ ] Configurar Prometheus para coletar métricas
- [ ] Monitorar flows recebidos por segundo
- [ ] Monitorar latência de processamento
- [ ] Monitorar uso de recursos

### Logs

- [ ] Configurar rotação de logs (logrotate)
- [ ] Centralizar logs (syslog, ELK, etc.)
- [ ] Configurar nível de log apropriado (info ou warn)
- [ ] Monitorar erros nos logs

### Alertas

- [ ] Configurar alertas para serviços down
- [ ] Alertas para queda na taxa de flows
- [ ] Alertas para uso de disco
- [ ] Alertas para falhas no ClickHouse
- [ ] Definir SLA e configurar alertas apropriados

## Dispositivos de Rede

### Configuração

- [ ] Configurar todos os dispositivos para enviar flows
- [ ] Usar sampling apropriado para o volume de tráfego
- [ ] Configurar source IP correto nos exporters
- [ ] Testar recepção de flows de cada dispositivo

### Validação

- [ ] Verificar flows chegando de todos os dispositivos
- [ ] Validar dados no ClickHouse
- [ ] Confirmar informações de interface
- [ ] Verificar enriquecimento (GeoIP, ASN)

## Documentação

### Interna

- [ ] Documentar arquitetura implementada
- [ ] Documentar procedimentos de operação
- [ ] Documentar procedimento de backup/restore
- [ ] Documentar troubleshooting comum
- [ ] Criar runbook para equipe de operações

### Configuração

- [ ] Manter cópia da configuração em controle de versão
- [ ] Documentar mudanças em changelog
- [ ] Manter inventário de dispositivos configurados
- [ ] Documentar IPs e portas utilizadas

## Compliance e Governança

### LGPD / GDPR

- [ ] Revisar dados coletados
- [ ] Implementar política de retenção adequada
- [ ] Garantir acesso restrito aos dados
- [ ] Documentar base legal para coleta

### Auditoria

- [ ] Habilitar logs de acesso
- [ ] Configurar auditoria de mudanças
- [ ] Revisar acessos periodicamente
- [ ] Manter histórico de mudanças

## Testes

### Funcionalidade

- [ ] Testar coleta de NetFlow
- [ ] Testar coleta de sFlow
- [ ] Testar coleta de IPFIX
- [ ] Testar interface web
- [ ] Testar queries no ClickHouse
- [ ] Testar exportação para Kafka

### Performance

- [ ] Teste de carga (simular volume esperado)
- [ ] Medir latência de processamento
- [ ] Validar performance de queries
- [ ] Testar sob carga máxima

### Recuperação

- [ ] Simular falha de container e recuperação
- [ ] Testar backup e restore
- [ ] Testar failover (se HA configurado)
- [ ] Validar procedimentos de DR

## Manutenção

### Atualizações

- [ ] Definir janela de manutenção
- [ ] Procedimento para atualização de versão
- [ ] Testar atualizações em ambiente não-produção primeiro
- [ ] Plano de rollback

### Limpeza

- [ ] Configurar limpeza automática de logs antigos
- [ ] Monitorar crescimento do banco de dados
- [ ] Limpar backups antigos automaticamente

## Go-Live

### Pré-Produção

- [ ] Todos os itens acima verificados
- [ ] Ambiente testado completamente
- [ ] Documentação atualizada
- [ ] Equipe treinada
- [ ] Procedimentos documentados

### Produção

- [ ] Migração planejada e aprovada
- [ ] Backup antes da migração
- [ ] Monitoramento ativo durante go-live
- [ ] Equipe em standby
- [ ] Plano de rollback pronto

### Pós-Produção

- [ ] Monitorar primeiras 24-48 horas intensivamente
- [ ] Validar dados coletados
- [ ] Ajustar configurações conforme necessário
- [ ] Coletar feedback dos usuários
- [ ] Documentar lições aprendidas

## Comandos de Verificação

```bash
# Status geral
./scripts/manage.sh status
./scripts/manage.sh health

# Verificar flows recebidos
docker exec akvorado-clickhouse clickhouse-client --query="
SELECT count() as total_flows
FROM akvorado.flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
"

# Verificar uso de disco
df -h

# Verificar recursos
docker stats --no-stream

# Verificar logs por erros
docker-compose logs --tail=1000 | grep -i error
```

## Contatos de Emergência

Manter lista atualizada de:
- [ ] Administrador do sistema
- [ ] Responsável pela rede
- [ ] Suporte técnico
- [ ] Escalação

---

## Template de Aprovação

```
Sistema: Akvorado Network Flow Analyzer
Data de Go-Live Planejada: __________
Ambiente: Produção

Checklist Completo: [ ] Sim [ ] Não

Aprovações:
- Infraestrutura:    __________________ Data: __________
- Segurança:         __________________ Data: __________
- Rede:              __________________ Data: __________
- Gerência:          __________________ Data: __________

Observações:
_____________________________________________________________
_____________________________________________________________
```

---

**Importante**: Não pule etapas deste checklist. Cada item é crítico para uma implementação bem-sucedida em produção.
