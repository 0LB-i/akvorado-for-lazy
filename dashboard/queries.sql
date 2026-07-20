-- QUERIES SQL ÚTEIS PARA ANÁLISE DE DADOS NO AKVORADO
-- Execute essas queries no ClickHouse para análise detalhada

-- ============================================
-- 1. TRÁFEGO EM TEMPO REAL
-- ============================================

-- Flows ativos nos últimos 5 minutos
SELECT
    count() as flows,
    sum(Bytes) as total_bytes,
    sum(Packets) as total_packets,
    avg(Bytes) as avg_bytes_per_flow
FROM flows
WHERE TimeReceived > now() - INTERVAL 5 MINUTE;

-- Tráfego por minuto (últimos 60 minutos)
SELECT
    toStartOfMinute(TimeReceived) as minute,
    count() as flows,
    sum(Bytes) / (1024 * 1024) as mb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY minute
ORDER BY minute DESC;


-- ============================================
-- 2. TOP TALKERS (IPs com maior tráfego)
-- ============================================

-- Top 20 IPs de origem por bytes enviados
SELECT
    SrcAddr,
    count() as flow_count,
    sum(Bytes) as total_bytes,
    sum(Packets) as total_packets,
    avg(Bytes) as avg_bytes
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY SrcAddr
ORDER BY total_bytes DESC
LIMIT 20;

-- Top 20 pares de IPs (conversações)
SELECT
    SrcAddr,
    DstAddr,
    count() as flow_count,
    sum(Bytes) as total_bytes,
    sum(Packets) as total_packets
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY SrcAddr, DstAddr
ORDER BY total_bytes DESC
LIMIT 20;

-- IPs que mais consomem bandwidth (bidirecionalmente)
SELECT
    ip,
    sum(total_bytes) as bandwidth
FROM (
    SELECT SrcAddr as ip, sum(Bytes) as total_bytes
    FROM flows
    WHERE TimeReceived > now() - INTERVAL 24 HOUR
    GROUP BY SrcAddr

    UNION ALL

    SELECT DstAddr as ip, sum(Bytes) as total_bytes
    FROM flows
    WHERE TimeReceived > now() - INTERVAL 24 HOUR
    GROUP BY DstAddr
)
GROUP BY ip
ORDER BY bandwidth DESC
LIMIT 20;


-- ============================================
-- 3. ANÁLISE GEOGRÁFICA
-- ============================================

-- Distribuição de tráfego por país (origem)
SELECT
    SrcCountry as country,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred,
    uniq(SrcAddr) as unique_ips
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND SrcCountry != ''
GROUP BY country
ORDER BY gb_transferred DESC;

-- Distribuição de tráfego por país (destino)
SELECT
    DstCountry as country,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred,
    uniq(DstAddr) as unique_ips
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND DstCountry != ''
GROUP BY country
ORDER BY gb_transferred DESC;

-- Tráfego internacional vs nacional (assumindo BR como nacional)
SELECT
    CASE
        WHEN SrcCountry = 'BR' AND DstCountry = 'BR' THEN 'Nacional'
        WHEN SrcCountry = 'BR' OR DstCountry = 'BR' THEN 'Internacional'
        ELSE 'Externo'
    END as traffic_type,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY traffic_type
ORDER BY gb_transferred DESC;


-- ============================================
-- 4. PROTOCOLOS E PORTAS
-- ============================================

-- Distribuição por protocolo
SELECT
    CASE Proto
        WHEN 1 THEN 'ICMP'
        WHEN 6 THEN 'TCP'
        WHEN 17 THEN 'UDP'
        WHEN 47 THEN 'GRE'
        WHEN 50 THEN 'ESP'
        WHEN 58 THEN 'ICMPv6'
        ELSE concat('Protocolo ', toString(Proto))
    END as protocol_name,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY Proto
ORDER BY gb_transferred DESC;

-- Top 30 portas de destino
SELECT
    DstPort,
    CASE DstPort
        WHEN 80 THEN 'HTTP'
        WHEN 443 THEN 'HTTPS'
        WHEN 22 THEN 'SSH'
        WHEN 21 THEN 'FTP'
        WHEN 25 THEN 'SMTP'
        WHEN 53 THEN 'DNS'
        WHEN 3306 THEN 'MySQL'
        WHEN 5432 THEN 'PostgreSQL'
        WHEN 6379 THEN 'Redis'
        WHEN 27017 THEN 'MongoDB'
        WHEN 3389 THEN 'RDP'
        WHEN 8080 THEN 'HTTP-Alt'
        WHEN 8443 THEN 'HTTPS-Alt'
        ELSE 'Unknown'
    END as service_name,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024) as mb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND DstPort > 0
GROUP BY DstPort
ORDER BY mb_transferred DESC
LIMIT 30;

-- Análise de portas altas (possível P2P ou malware)
SELECT
    DstPort,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024) as mb_transferred,
    uniq(SrcAddr) as unique_sources
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND DstPort > 10000
GROUP BY DstPort
ORDER BY flow_count DESC
LIMIT 20;


-- ============================================
-- 5. ANÁLISE DE TRÁFEGO SUSPEITO
-- ============================================

-- Port Scanning (múltiplas tentativas de conexão)
SELECT
    SrcAddr,
    uniq(DstPort) as ports_scanned,
    count() as connection_attempts,
    uniq(DstAddr) as targets_count
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY SrcAddr
HAVING ports_scanned > 50 OR connection_attempts > 500
ORDER BY ports_scanned DESC;

-- Detecção de DDoS (múltiplos IPs atacando o mesmo destino)
SELECT
    DstAddr,
    DstPort,
    uniq(SrcAddr) as attacking_ips,
    count() as total_flows,
    sum(Packets) as total_packets
FROM flows
WHERE TimeReceived > now() - INTERVAL 15 MINUTE
GROUP BY DstAddr, DstPort
HAVING attacking_ips > 100
ORDER BY attacking_ips DESC;

-- Transferência massiva de dados (possível exfiltração)
SELECT
    SrcAddr,
    DstAddr,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred,
    count() as flow_count,
    avg(Bytes / nullIf(Duration, 0)) as avg_bandwidth
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY SrcAddr, DstAddr
HAVING gb_transferred > 10
ORDER BY gb_transferred DESC;

-- Conexões para países suspeitos (ajuste conforme necessidade)
SELECT
    SrcAddr,
    DstAddr,
    DstCountry,
    count() as connection_count,
    sum(Bytes) / (1024 * 1024) as mb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND DstCountry IN ('CN', 'RU', 'KP', 'IR')
GROUP BY SrcAddr, DstAddr, DstCountry
ORDER BY mb_transferred DESC;

-- Tráfego fora do horário comercial (suspeito)
SELECT
    SrcAddr,
    DstAddr,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND (toHour(TimeReceived) < 6 OR toHour(TimeReceived) > 22)
GROUP BY SrcAddr, DstAddr
HAVING gb_transferred > 5
ORDER BY gb_transferred DESC;

-- IPs com comportamento anômalo (muitas portas diferentes)
SELECT
    SrcAddr,
    uniq(DstPort) as unique_ports,
    uniq(DstAddr) as unique_destinations,
    count() as total_flows
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY SrcAddr
HAVING unique_ports > 100
ORDER BY unique_ports DESC;


-- ============================================
-- 6. ESTATÍSTICAS GERAIS
-- ============================================

-- Resumo geral das últimas 24 horas
SELECT
    count() as total_flows,
    sum(Bytes) / (1024 * 1024 * 1024) as total_gb,
    sum(Packets) as total_packets,
    uniq(SrcAddr) as unique_src_ips,
    uniq(DstAddr) as unique_dst_ips,
    avg(Bytes) as avg_flow_size,
    median(Bytes) as median_flow_size
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR;

-- Tráfego por hora (últimas 24 horas)
SELECT
    toStartOfHour(TimeReceived) as hour,
    count() as flows,
    sum(Bytes) / (1024 * 1024 * 1024) as gb,
    sum(Packets) / 1000000 as millions_packets
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC;

-- Top ASNs (Autonomous System Numbers)
SELECT
    SrcAS,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred,
    uniq(SrcAddr) as unique_ips
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
    AND SrcAS > 0
GROUP BY SrcAS
ORDER BY gb_transferred DESC
LIMIT 20;


-- ============================================
-- 7. ANÁLISE DE PERFORMANCE
-- ============================================

-- Latência média por destino (se disponível)
SELECT
    DstAddr,
    avg(Duration) as avg_duration,
    count() as flow_count
FROM flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
    AND Duration > 0
GROUP BY DstAddr
ORDER BY avg_duration DESC
LIMIT 20;

-- Taxa de retransmissão (se disponível)
SELECT
    toStartOfHour(TimeReceived) as hour,
    avg(Bytes / nullIf(Packets, 0)) as avg_packet_size,
    sum(Bytes) / sum(Packets) as overall_avg
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour DESC;


-- ============================================
-- 8. QUERIES DE MANUTENÇÃO
-- ============================================

-- Verificar tamanho da tabela
SELECT
    table,
    formatReadableSize(sum(bytes)) as size,
    sum(rows) as rows,
    max(modification_time) as latest_modification
FROM system.parts
WHERE table = 'flows'
GROUP BY table;

-- Verificar partições
SELECT
    partition,
    sum(rows) as rows,
    formatReadableSize(sum(bytes)) as size
FROM system.parts
WHERE table = 'flows'
    AND active
GROUP BY partition
ORDER BY partition DESC;

-- Limpar flows antigos (cuidado!)
-- ALTER TABLE flows DELETE WHERE TimeReceived < now() - INTERVAL 30 DAY;


-- ============================================
-- 9. QUERIES PARA RELATÓRIOS
-- ============================================

-- Relatório diário de tráfego
SELECT
    toDate(TimeReceived) as date,
    count() as total_flows,
    sum(Bytes) / (1024 * 1024 * 1024) as total_gb,
    uniq(SrcAddr) as unique_sources,
    uniq(DstAddr) as unique_destinations
FROM flows
WHERE TimeReceived > now() - INTERVAL 7 DAY
GROUP BY date
ORDER BY date DESC;

-- Top 10 aplicações por tráfego (baseado em portas)
SELECT
    CASE
        WHEN DstPort = 80 OR DstPort = 8080 THEN 'HTTP'
        WHEN DstPort = 443 OR DstPort = 8443 THEN 'HTTPS'
        WHEN DstPort = 22 THEN 'SSH'
        WHEN DstPort = 21 THEN 'FTP'
        WHEN DstPort = 25 OR DstPort = 587 THEN 'Email'
        WHEN DstPort = 53 THEN 'DNS'
        WHEN DstPort >= 6881 AND DstPort <= 6889 THEN 'BitTorrent'
        WHEN DstPort = 3389 THEN 'RDP'
        ELSE 'Other'
    END as application,
    count() as flow_count,
    sum(Bytes) / (1024 * 1024 * 1024) as gb_transferred
FROM flows
WHERE TimeReceived > now() - INTERVAL 24 HOUR
GROUP BY application
ORDER BY gb_transferred DESC;
