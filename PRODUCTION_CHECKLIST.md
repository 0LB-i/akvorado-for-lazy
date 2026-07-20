# Checklist para Produção - Akvorado

Use este checklist antes de colocar o Akvorado em produção.

## Segurança

### Senhas e Credenciais

- [ ] Alterar senha do ClickHouse no `.env` (CLICKHOUSE_PASSWORD)
- [ ] Alterar senha do Redis no `.env` (REDIS_PASSWORD)
- [ ] Gerar senhas fortes (mínimo 16 caracteres)
- [ ] Armazenar credenciais em local seguro (vault/password manager)

### Autenticação

- [ ] Habilitar autenticação no Console (`config/akvorado.yaml`)
- [ ] Criar usuários com senhas bcrypt
- [ ] Configurar níveis de acesso (se aplicável)
- [ ] Testar login na interface web

### Firewall

- [ ] Configurar firewall do servidor
- [ ] Permitir apenas IPs autorizados nas portas de gerenciamento (8000, 8080, 8123)
- [ ] Permitir IPs dos dispositivos de rede nas portas de flow (2055, 6343, 4739)
- [ ] Bloquear acesso direto ao Kafka/Zookeeper de fora
- [ ] Considerar VPN para acesso administrativo

Exemplo UFW:
```bash
# Gerenciamento (apenas IPs autorizados)
ufw allow from 192.168.1.0/24 to any port 8000 proto tcp
ufw allow from 192.168.1.0/24 to any port 8080 proto tcp

# Flows (dispositivos de rede)
ufw allow from 10.0.0.0/8 to any port 2055 proto udp
ufw allow from 10.0.0.0/8 to any port 6343 proto udp
ufw allow from 10.0.0.0/8 to any port 4739 proto udp
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

- [ ] Ajustar WORKERS no `.env` (recomendado: número de CPUs)
- [ ] Configurar FLOW_BUFFER_SIZE adequadamente
- [ ] Definir MAX_FLOWS_PER_SECOND baseado no ambiente
- [ ] Otimizar cache do ClickHouse

### Monitoramento de Recursos

- [ ] Configurar alertas de CPU > 80%
- [ ] Configurar alertas de RAM > 80%
- [ ] Configurar alertas de disco > 80%
- [ ] Monitorar I/O do disco

## Dados

### Retenção

- [ ] Definir política de retenção apropriada
- [ ] Configurar em `config/akvorado.yaml`:
  - flows: 168h (7 dias) ou conforme necessário
  - aggregated: 2160h (90 dias) ou conforme necessário
- [ ] Calcular espaço em disco necessário
- [ ] Testar limpeza automática

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
