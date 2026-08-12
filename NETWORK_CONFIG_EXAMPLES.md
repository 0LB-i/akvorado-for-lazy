# Exemplos de Configuração de Dispositivos de Rede

Este documento contém exemplos de configuração para diversos fabricantes de equipamentos de rede para enviar flows ao Akvorado.

⚠️ **Importante**: Substitua `<AKVORADO_IP>` pelo IP do servidor onde o Akvorado está instalado.

## Cisco IOS / IOS-XE

### NetFlow v9

```cisco
! Habilitar NetFlow v9
ip flow-export version 9
ip flow-export destination <AKVORADO_IP> 2055

! Configurar cache
ip flow-cache timeout active 1
ip flow-cache timeout inactive 15

! Aplicar em interfaces
interface GigabitEthernet0/0
 ip flow ingress
 ip flow egress
!

interface GigabitEthernet0/1
 ip flow ingress
 ip flow egress
!
```

### NetFlow v5

```cisco
! Habilitar NetFlow v5
ip flow-export version 5
ip flow-export destination <AKVORADO_IP> 2055

! Configurar source (IP do roteador)
ip flow-export source GigabitEthernet0/0

! Aplicar em interfaces
interface GigabitEthernet0/1
 ip route-cache flow
!
```

### Flexible NetFlow (FNF)

```cisco
! Definir flow record
flow record AKVORADO-RECORD
 match ipv4 protocol
 match ipv4 source address
 match ipv4 destination address
 match transport source-port
 match transport destination-port
 collect interface input
 collect interface output
 collect counter bytes
 collect counter packets
 collect timestamp sys-uptime first
 collect timestamp sys-uptime last
!

! Definir flow exporter
flow exporter AKVORADO-EXPORTER
 destination <AKVORADO_IP>
 transport udp 2055
 export-protocol netflow-v9
 template data timeout 60
!

! Definir flow monitor
flow monitor AKVORADO-MONITOR
 exporter AKVORADO-EXPORTER
 record AKVORADO-RECORD
 cache timeout active 60
!

! Aplicar em interfaces
interface GigabitEthernet0/0
 ip flow monitor AKVORADO-MONITOR input
 ip flow monitor AKVORADO-MONITOR output
!
```

## Cisco NX-OS (Nexus)

### NetFlow

```cisco
! Habilitar feature
feature netflow

! Configurar flow exporter
flow exporter AKVORADO
 destination <AKVORADO_IP> use-vrf default
 transport udp 2055
 source mgmt0
 version 9
!

! Configurar flow record
flow record AKVORADO-RECORD
 match ipv4 source address
 match ipv4 destination address
 match ip protocol
 match ip tos
 match transport source-port
 match transport destination-port
 collect counter bytes
 collect counter packets
 collect timestamp sys-uptime first
 collect timestamp sys-uptime last
!

! Configurar flow monitor
flow monitor AKVORADO-MONITOR
 record AKVORADO-RECORD
 exporter AKVORADO
!

! Aplicar em interfaces
interface Ethernet1/1
 ip flow monitor AKVORADO-MONITOR input
 ip flow monitor AKVORADO-MONITOR output
!
```

## Juniper JunOS

### IPFIX

```juniper
# Configurar sampling
set chassis fpc 0 sampling-instance AKVORADO
set chassis fpc 0 inline-services flow-table-size 10
set forwarding-options sampling instance AKVORADO family inet output flow-server <AKVORADO_IP> port 4739
set forwarding-options sampling instance AKVORADO family inet output flow-server <AKVORADO_IP> version-ipfix template AKVORADO-TEMPLATE
set forwarding-options sampling instance AKVORADO family inet output inline-jflow source-address <ROUTER_IP>

# Definir template
set services flow-monitoring version-ipfix template AKVORADO-TEMPLATE flow-active-timeout 60
set services flow-monitoring version-ipfix template AKVORADO-TEMPLATE flow-inactive-timeout 30
set services flow-monitoring version-ipfix template AKVORADO-TEMPLATE template-refresh-rate packets 30
set services flow-monitoring version-ipfix template AKVORADO-TEMPLATE template-refresh-rate seconds 60

# Aplicar em interfaces
set interfaces ge-0/0/0 unit 0 family inet sampling input
set interfaces ge-0/0/0 unit 0 family inet sampling output
```

### sFlow

```juniper
# Configurar sFlow
set protocols sflow collector <AKVORADO_IP> udp-port 6343
set protocols sflow source-ip <ROUTER_IP>
set protocols sflow polling-interval 20
set protocols sflow sample-rate ingress 1000

# Aplicar em interfaces
set protocols sflow interfaces ge-0/0/0
set protocols sflow interfaces ge-0/0/1
```

## MikroTik RouterOS

### NetFlow

```routeros
# Habilitar NetFlow
/ip traffic-flow
set enabled=yes
set interfaces=all
set active-flow-timeout=1m
set inactive-flow-timeout=15s

# Configurar target
/ip traffic-flow target
add address=<AKVORADO_IP>:2055 version=9

# (Opcional) Configurar sampling
set cache-entries=16k
```

## HPE / Aruba

### sFlow

```aruba
# Habilitar sFlow globalmente
sflow enable

# Configurar collector
sflow collector <AKVORADO_IP> port 6343

# Configurar polling e sampling
sflow polling-interval 20
sflow sample-rate 1024

# Habilitar em interfaces
interface 1
 sflow enable
!
interface 2
 sflow enable
!
```

## Huawei VRP

### NetFlow

```huawei
# Configurar NetFlow
ip netstream timeout active 1
ip netstream timeout inactive 15
ip netstream export version 9
ip netstream export source <ROUTER_IP>
ip netstream export host <AKVORADO_IP> 2055

# Aplicar em interfaces
interface GigabitEthernet0/0/1
 ip netstream inbound
 ip netstream outbound
!
```

## Dell/Force10

### sFlow

```dell
# Configurar sFlow globalmente
sflow enable

# Configurar collector
sflow collector <AKVORADO_IP> port 6343 owner akvorado

# Configurar sampling
sflow sample-rate 4096

# Habilitar em interfaces
interface TenGigabitEthernet 1/1
 sflow enable
!
```

## Extreme Networks

### sFlow

```extreme
# Habilitar sFlow
enable sflow

# Configurar collector
configure sflow collector <AKVORADO_IP> port 6343 vr VR-Default

# Configurar sample rate
configure sflow sample-rate 2048

# Habilitar em portas
enable sflow ports 1-24
```

## Ubiquiti EdgeRouter

### NetFlow

```ubiquiti
set system flow-accounting interface eth0
set system flow-accounting interface eth1
set system flow-accounting netflow server <AKVORADO_IP> port 2055
set system flow-accounting netflow version 9
set system flow-accounting netflow timeout expiry-interval 60
```

## Linux (com softflowd)

### softflowd - NetFlow/IPFIX Exporter

```bash
# Instalar
apt-get install softflowd

# Configurar
nano /etc/default/softflowd

# Adicionar:
INTERFACE="eth0"
OPTIONS="-v 9 -n <AKVORADO_IP>:2055 -t maxlife=60"

# Iniciar
systemctl enable softflowd
systemctl start softflowd

# Verificar
systemctl status softflowd
softflowd -d
```

## pfSense / OPNsense

### NetFlow

1. Acesse **System → Advanced → Miscellaneous**
2. Habilite **NetFlow**
3. Configure:
   - NetFlow Server: `<AKVORADO_IP>:2055`
   - NetFlow Version: `9`
4. Salve e aplique

Ou via CLI:

```bash
# Instalar softflowd
pkg install softflowd

# Configurar
cat > /usr/local/etc/softflowd.conf << EOF
interface: em0
netflow-version: 9
collector-host: <AKVORADO_IP>
collector-port: 2055
EOF

# Habilitar
service softflowd enable
service softflowd start
```

## Verificação

Após configurar, verifique se os flows estão chegando:

### No servidor Akvorado

```bash
# Verificar pacotes UDP nas portas
sudo tcpdump -i any port 2055 or port 6343 or port 4739 -n

# Verificar logs do inlet
docker-compose logs akvorado-inlet

# Verificar dados no ClickHouse
docker exec akvorado-clickhouse clickhouse-client --query="
SELECT
    SrcAddr,
    DstAddr,
    Bytes,
    Packets
FROM akvorado.flows
ORDER BY TimeReceived DESC
LIMIT 10
"
```

## Dicas de Performance

### Sampling Rate

Para redes com muito tráfego, use sampling:

- **Pequeno (< 1 Gbps)**: 1:100 ou sem sampling
- **Médio (1-10 Gbps)**: 1:1000
- **Grande (> 10 Gbps)**: 1:10000

### Active Timeout

- **Recomendado**: 60 segundos
- **Tráfego alto**: 30 segundos
- **Tráfego baixo**: 120 segundos

### Inactive Timeout

- **Recomendado**: 15 segundos
- **Redes latentes**: 30 segundos

## Troubleshooting

### Flows não aparecem

1. **Verificar conectividade**:
```bash
# Do roteador para o Akvorado
ping <AKVORADO_IP>
```

2. **Verificar firewall**:
```bash
# Permitir UDP nas portas
ufw allow 2055/udp
ufw allow 6343/udp
ufw allow 4739/udp
```

3. **Verificar NAT**:
- Se o Akvorado está atrás de NAT, configure port forwarding

4. **Verificar logs**:
```bash
# Logs do dispositivo
show logging | include flow

# Logs do Akvorado
docker-compose logs akvorado-inlet
```

## Referências

- Cisco NetFlow: https://www.cisco.com/c/en/us/tech/quality-of-service-qos/netflow/index.html
- Juniper IPFIX: https://www.juniper.net/documentation/us/en/software/junos/flow-monitoring/
- sFlow: https://sflow.org/
- IPFIX: https://www.ietf.org/rfc/rfc7011.txt

---

**Nota**: Sempre consulte a documentação específica do seu equipamento para configurações detalhadas.
