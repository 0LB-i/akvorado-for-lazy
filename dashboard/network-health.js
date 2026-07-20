// Network Health Dashboard JavaScript

let config = {
    clickhouse: {
        host: '170.244.221.231:8123',
        user: 'akvorado',
        password: 'akvorado123',
        database: 'akvorado'
    },
    thresholds: {
        asymmetry: 10, // Razão >10x indica problema
        blackhole: 1000, // >1000 pacotes sem resposta
        fragmentationPercent: 30, // >30% de pacotes pequenos
        concentrationPercent: 50, // Um destino com >50% do tráfego
        interfaceUtilization: 80 // >80% de utilização
    },
    refreshInterval: 60000 // 60 segundos
};

let healthScore = {
    total: 100,
    issues: []
};

// Carregar configurações
function loadSettings() {
    const savedHost = localStorage.getItem('clickhouse-host');
    const savedUser = localStorage.getItem('clickhouse-user');
    const savedPass = localStorage.getItem('clickhouse-pass');

    if (savedHost) config.clickhouse.host = savedHost;
    if (savedUser) config.clickhouse.user = savedUser;
    if (savedPass) config.clickhouse.password = savedPass;
}

// Obter intervalo de tempo
function getTimeRange() {
    const select = document.getElementById('time-range');
    return select ? parseInt(select.value) : 24;
}

// Executar query no ClickHouse
async function executeQuery(query) {
    try {
        const url = `http://${config.clickhouse.host}/?database=${config.clickhouse.database}&user=${config.clickhouse.user}&password=${config.clickhouse.password}`;

        const response = await fetch(url, {
            method: 'POST',
            body: query,
            headers: { 'Content-Type': 'text/plain' }
        });

        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }

        const data = await response.json();
        return data;
    } catch (error) {
        console.error('Erro ao executar query:', error);
        return null;
    }
}

// Formatar bytes
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// Formatar números
function formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(2) + 'K';
    return num.toString();
}

// Obter bandeira do país
function getCountryFlag(country) {
    const flags = {
        'BR': '🇧🇷', 'US': '🇺🇸', 'CN': '🇨🇳', 'RU': '🇷🇺',
        'DE': '🇩🇪', 'GB': '🇬🇧', 'FR': '🇫🇷', 'JP': '🇯🇵',
        'AR': '🇦🇷', 'CL': '🇨🇱', 'MX': '🇲🇽', 'IN': '🇮🇳',
        'KR': '🇰🇷', 'NL': '🇳🇱', 'CA': '🇨🇦', 'AU': '🇦🇺'
    };
    return flags[country] || '🌐';
}

// Obter nome do provedor por ASN
function getASNName(asn) {
    const asnNames = {
        '15169': 'Google LLC', '16509': 'Amazon AWS', '13335': 'Cloudflare',
        '8075': 'Microsoft', '32934': 'Facebook/Meta', '714': 'Apple',
        '20940': 'Akamai', '2906': 'Netflix', '28573': 'Claro/NET',
        '26599': 'TELEFÔNICA BRASIL', '7738': 'Telemar/Oi',
        '263263': 'Gwtelecom', '53062': 'BRISANET', '268113': 'W5 Telecom',
        '28604': 'Tely Telecom', '14061': 'DigitalOcean', '63949': 'Linode',
        '24940': 'Hetzner', '16276': 'OVH', '174': 'Cogent',
        '3356': 'Level3/Lumen', '6939': 'Hurricane Electric'
    };
    return asnNames[asn.toString()] || `AS${asn}`;
}

// Resetar health score
function resetHealthScore() {
    healthScore = { total: 100, issues: [] };
}

// Deduzir pontos do health score
function deductHealthScore(points, issue) {
    healthScore.total = Math.max(0, healthScore.total - points);
    healthScore.issues.push(issue);
}

// Mostrar alerta
function showAlert(type, message) {
    const alertsDiv = document.getElementById('health-alerts');
    const alertClass = type === 'critical' ? 'alert-critical' :
                      type === 'warning' ? 'alert-warning' : 'alert-info';

    const alert = document.createElement('div');
    alert.className = `alert-box ${alertClass}`;
    alert.innerHTML = `<strong>${message}</strong>`;
    alertsDiv.appendChild(alert);
}

// Detectar Assimetria de Tráfego
async function detectTrafficAsymmetry() {
    const hours = getTimeRange();

    const query = `
        WITH outbound AS (
            SELECT
                SrcAddr as ip,
                any(SrcCountry) as country,
                any(SrcAS) as asn,
                sum(Bytes) as bytes_sent,
                count() as flows_sent
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
              AND OutIfBoundary = 'external'
            GROUP BY ip
        ),
        inbound AS (
            SELECT
                DstAddr as ip,
                sum(Bytes) as bytes_received,
                count() as flows_received
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
              AND InIfBoundary = 'external'
            GROUP BY ip
        )
        SELECT
            o.ip,
            o.country,
            o.asn,
            o.bytes_sent,
            COALESCE(i.bytes_received, 0) as bytes_received,
            o.bytes_sent / (COALESCE(i.bytes_received, 1)) as ratio
        FROM outbound o
        LEFT JOIN inbound i ON o.ip = i.ip
        WHERE bytes_sent > 1000000
          AND ratio > ${config.thresholds.asymmetry}
        ORDER BY ratio DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#asymmetry-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = row.ratio > 100 ? 'critical' :
                           row.ratio > 50 ? 'warning' : 'info';
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.ip}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${formatBytes(row.bytes_sent)}</td>
                <td>${formatBytes(row.bytes_received)}</td>
                <td class="${severity}">${row.ratio.toFixed(1)}x</td>
                <td class="${severity}">${severity === 'critical' ? '🔴 Crítico' : severity === 'warning' ? '🟡 Aviso' : '🔵 Info'}</td>
            `;
            tbody.appendChild(tr);

            if (severity === 'critical') {
                deductHealthScore(5, `Assimetria crítica: ${row.ip}`);
            }
        });

        if (data.data.filter(r => r.ratio > 100).length > 0) {
            showAlert('warning', `${data.data.filter(r => r.ratio > 100).length} IP(s) com assimetria crítica de tráfego!`);
        }
    } else {
        document.querySelector('#asymmetry-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhuma assimetria significativa detectada</td></tr>';
    }
}

// Detectar Blackholes de Rede
async function detectNetworkBlackholes() {
    const hours = getTimeRange();

    const query = `
        WITH sent AS (
            SELECT
                DstAddr as ip,
                any(DstCountry) as country,
                any(DstAS) as asn,
                uniq(SrcAddr) as sources,
                sum(Packets) as packets_sent,
                sum(Bytes) as bytes_sent
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
              AND OutIfBoundary = 'external'
            GROUP BY ip
            HAVING packets_sent > ${config.thresholds.blackhole}
        ),
        received AS (
            SELECT
                SrcAddr as ip,
                sum(Packets) as packets_received
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
              AND InIfBoundary = 'external'
            GROUP BY ip
        )
        SELECT
            s.ip,
            s.country,
            s.asn,
            s.sources,
            s.packets_sent,
            s.bytes_sent,
            COALESCE(r.packets_received, 0) as packets_received,
            s.packets_sent / (COALESCE(r.packets_received, 1)) as ratio
        FROM sent s
        LEFT JOIN received r ON s.ip = r.ip
        WHERE ratio > 10
        ORDER BY packets_sent DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#blackholes-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';
            const status = row.packets_received === 0 ? 'Blackhole Total' : 'Blackhole Parcial';
            const statusClass = row.packets_received === 0 ? 'status-critical' : 'status-degraded';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.ip}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${row.sources}</td>
                <td>${formatNumber(row.packets_sent)}</td>
                <td>${formatBytes(row.bytes_sent)}</td>
                <td><span class="status-badge ${statusClass}">${status}</span></td>
            `;
            tbody.appendChild(tr);

            if (row.packets_received === 0) {
                deductHealthScore(10, `Blackhole detectado: ${row.ip}`);
            }
        });

        const totalBlackholes = data.data.filter(r => r.packets_received === 0).length;
        if (totalBlackholes > 0) {
            showAlert('critical', `${totalBlackholes} blackhole(s) de rede detectado(s)! IPs não estão respondendo.`);
        }
    } else {
        document.querySelector('#blackholes-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum blackhole de rede detectado</td></tr>';
    }
}

// Detectar Fragmentação de Pacotes
async function detectPacketFragmentation() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            count() as total_flows,
            avg(Bytes / Packets) as avg_packet_size,
            countIf(Bytes / Packets < 64) as small_packets,
            (small_packets / total_flows * 100) as fragmentation_percent
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND Packets > 0
        GROUP BY SrcAddr, DstAddr
        HAVING total_flows > 100
          AND fragmentation_percent > ${config.thresholds.fragmentationPercent}
        ORDER BY fragmentation_percent DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#fragmentation-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = row.fragmentation_percent > 70 ? 'critical' :
                           row.fragmentation_percent > 50 ? 'warning' : 'info';
            const problem = row.avg_packet_size < 64 ? 'MTU muito pequeno' :
                          row.avg_packet_size < 200 ? 'Possível fragmentação' : 'Alto overhead';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${formatNumber(row.total_flows)}</td>
                <td>${Math.round(row.avg_packet_size)}</td>
                <td>${formatNumber(row.small_packets)}</td>
                <td class="${severity}">${row.fragmentation_percent.toFixed(1)}%</td>
                <td class="${severity}">${problem}</td>
            `;
            tbody.appendChild(tr);

            if (severity === 'critical') {
                deductHealthScore(3, `Fragmentação crítica: ${row.SrcAddr} → ${row.DstAddr}`);
            }
        });

        if (data.data.filter(r => r.fragmentation_percent > 70).length > 0) {
            showAlert('warning', 'Fragmentação excessiva de pacotes detectada! Verifique configurações de MTU.');
        }
    } else {
        document.querySelector('#fragmentation-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Fragmentação de pacotes dentro do normal</td></tr>';
    }
}

// Detectar Concentração de Tráfego
async function detectTrafficConcentration() {
    const hours = getTimeRange();

    const query = `
        WITH total_traffic AS (
            SELECT sum(Bytes) as total_bytes
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        )
        SELECT
            DstAddr,
            any(DstCountry) as country,
            any(DstAS) as asn,
            uniq(SrcAddr) as sources,
            sum(Bytes) as bytes,
            (bytes / (SELECT total_bytes FROM total_traffic) * 100) as percent_of_total
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        GROUP BY DstAddr
        ORDER BY bytes DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#concentration-table tbody');
        tbody.innerHTML = '';

        let rank = 1;
        data.data.forEach(row => {
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';
            const barClass = row.percent_of_total > 50 ? 'critical' :
                           row.percent_of_total > 30 ? 'warning' : '';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${rank++}</td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${formatNumber(row.sources)}</td>
                <td>
                    ${row.percent_of_total.toFixed(2)}%
                    <div class="percentage-bar">
                        <div class="percentage-fill ${barClass}" style="width: ${Math.min(100, row.percent_of_total)}%"></div>
                    </div>
                </td>
                <td>${formatBytes(row.bytes)}</td>
            `;
            tbody.appendChild(tr);

            if (row.percent_of_total > 50) {
                deductHealthScore(5, `Concentração excessiva: ${row.DstAddr} (${row.percent_of_total.toFixed(1)}%)`);
            }
        });

        if (data.data[0] && data.data[0].percent_of_total > 50) {
            showAlert('warning', `Tráfego muito concentrado! ${data.data[0].percent_of_total.toFixed(1)}% do tráfego vai para um único destino.`);
        }
    }
}

// Analisar Saúde das Interfaces
async function analyzeInterfaceHealth() {
    const hours = getTimeRange();

    const query = `
        SELECT
            concat(InIfName, ' → ', OutIfName) as interface,
            CASE
                WHEN InIfBoundary = 'external' THEN 'Entrada'
                WHEN OutIfBoundary = 'external' THEN 'Saída'
                ELSE 'Interno'
            END as direction,
            count() as flows,
            sum(Bytes) as bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND (InIfName != '' OR OutIfName != '')
        GROUP BY interface, direction
        ORDER BY bytes DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#interfaces-table tbody');
        tbody.innerHTML = '';

        // Calcular utilização assumindo 10Gbps como capacidade padrão
        const capacityBps = 10 * 1000 * 1000 * 1000; // 10 Gbps
        const timeSeconds = hours * 3600;

        data.data.forEach(row => {
            const utilizationPercent = (row.bytes * 8 / timeSeconds / capacityBps * 100);
            const status = utilizationPercent > 80 ? 'Saturada' :
                          utilizationPercent > 60 ? 'Alta' :
                          utilizationPercent > 40 ? 'Moderada' : 'Normal';
            const statusClass = utilizationPercent > 80 ? 'status-critical' :
                              utilizationPercent > 60 ? 'status-degraded' : 'status-healthy';
            const barClass = utilizationPercent > 80 ? 'critical' :
                           utilizationPercent > 60 ? 'warning' : '';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="interface-badge">${row.interface}</span></td>
                <td>${row.direction}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatBytes(row.bytes)}</td>
                <td>
                    ${utilizationPercent.toFixed(1)}%
                    <div class="percentage-bar">
                        <div class="percentage-fill ${barClass}" style="width: ${Math.min(100, utilizationPercent)}%"></div>
                    </div>
                </td>
                <td><span class="status-badge ${statusClass}">${status}</span></td>
            `;
            tbody.appendChild(tr);

            if (utilizationPercent > 80) {
                deductHealthScore(10, `Interface saturada: ${row.interface}`);
            }
        });

        const saturatedInterfaces = data.data.filter((r, i) => {
            const utilizationPercent = (r.bytes * 8 / timeSeconds / capacityBps * 100);
            return utilizationPercent > 80;
        }).length;

        if (saturatedInterfaces > 0) {
            showAlert('critical', `${saturatedInterfaces} interface(s) com alta utilização! Possível saturação.`);
        }

        document.getElementById('monitored-interfaces').textContent = data.data.length;
    } else {
        document.querySelector('#interfaces-table tbody').innerHTML =
            '<tr><td colspan="6" style="text-align: center; color: #6b7280;">Nenhuma interface detectada</td></tr>';
        document.getElementById('monitored-interfaces').textContent = '0';
    }
}

// Detectar Falhas de Conexão
async function detectConnectionFailures() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            DstPort,
            count() as attempts,
            countIf(Bytes < 1000) as failed_attempts,
            (failed_attempts / attempts * 100) as failure_rate
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND OutIfBoundary = 'external'
        GROUP BY SrcAddr, DstAddr, DstPort
        HAVING attempts > 50
          AND failure_rate > 50
        ORDER BY failed_attempts DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#connection-failures-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const possibleCause = row.DstPort === 80 || row.DstPort === 443 ? 'Servidor web offline' :
                                 row.DstPort === 22 ? 'SSH bloqueado/offline' :
                                 row.DstPort === 25 ? 'Servidor SMTP offline' :
                                 row.failure_rate > 90 ? 'Destino inacessível' :
                                 'Rede instável';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.DstPort}</td>
                <td class="critical">${formatNumber(row.failed_attempts)}</td>
                <td class="critical">${row.failure_rate.toFixed(1)}%</td>
                <td>${possibleCause}</td>
            `;
            tbody.appendChild(tr);

            deductHealthScore(2, `Falhas de conexão: ${row.SrcAddr} → ${row.DstAddr}:${row.DstPort}`);
        });

        showAlert('warning', `${data.data.length} par(es) de IP com alta taxa de falha de conexão detectado(s).`);
    } else {
        document.querySelector('#connection-failures-table tbody').innerHTML =
            '<tr><td colspan="6" style="text-align: center; color: #10b981;">✓ Nenhuma falha significativa de conexão detectada</td></tr>';
    }
}

// Detectar Protocolos Anômalos
async function detectAnomalousProtocols() {
    const hours = getTimeRange();

    const query = `
        SELECT
            DstPort,
            Proto,
            count() as flows,
            uniq(SrcAddr) + uniq(DstAddr) as unique_ips,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND DstPort NOT IN (80, 443, 53, 22, 25, 21, 3389, 8080, 8443)
          AND DstPort > 1024
        GROUP BY DstPort, Proto
        HAVING flows > 1000
        ORDER BY flows DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#anomalous-protocols-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const protoName = row.Proto === 6 ? 'TCP' : row.Proto === 17 ? 'UDP' : `Proto ${row.Proto}`;
            const anomalyType = row.unique_ips > 1000 ? 'Possível Botnet' :
                              row.flows > 10000 ? 'Tráfego Intenso' :
                              'Porta Não Padrão';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><strong>${row.DstPort}</strong></td>
                <td>${protoName}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatNumber(row.unique_ips)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td class="warning">${anomalyType}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#anomalous-protocols-table tbody').innerHTML =
            '<tr><td colspan="6" style="text-align: center; color: #10b981;">✓ Uso de protocolos dentro do padrão</td></tr>';
    }
}

// Analisar ASNs com Problemas
async function analyzeProblematicASNs() {
    const hours = getTimeRange();

    const query = `
        WITH asn_stats AS (
            SELECT
                SrcAS as asn,
                any(SrcCountry) as country,
                count() as total_flows,
                sum(Bytes) as total_bytes,
                countIf(Bytes < 1000) as small_flows,
                uniq(DstPort) as unique_ports
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
              AND SrcAS > 0
            GROUP BY asn
        )
        SELECT
            asn,
            country,
            total_flows,
            small_flows,
            unique_ports,
            (small_flows / total_flows * 100) as failure_rate
        FROM asn_stats
        WHERE total_flows > 100
          AND (failure_rate > 40 OR unique_ports > 1000)
        ORDER BY failure_rate DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#asn-problems-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const providerName = getASNName(row.asn);
            const problemType = row.failure_rate > 60 ? 'Alta taxa de falha' :
                              row.unique_ports > 1000 ? 'Port Scanning' :
                              'Conectividade instável';
            const severity = row.failure_rate > 60 || row.unique_ports > 1000 ? 'critical' : 'warning';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>AS${row.asn}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td>${formatNumber(row.small_flows)} de ${formatNumber(row.total_flows)}</td>
                <td class="${severity}">${problemType}</td>
                <td class="${severity}">${severity === 'critical' ? '🔴 Crítico' : '🟡 Aviso'}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#asn-problems-table tbody').innerHTML =
            '<tr><td colspan="6" style="text-align: center; color: #10b981;">✓ Nenhum ASN com problemas detectado</td></tr>';
    }
}

// Atualizar Timeline de Problemas
async function updateProblemsTimeline() {
    const hours = getTimeRange();

    const query = `
        SELECT
            toStartOfHour(TimeReceived) as hour,
            countIf(Bytes < 1000) as connection_failures,
            countIf(Bytes / Packets < 64 AND Packets > 0) as fragmented_packets,
            count() as total_flows
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        GROUP BY hour
        ORDER BY hour
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const labels = data.data.map(row => {
            const date = new Date(row.hour);
            return date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
        });
        const failures = data.data.map(row => row.connection_failures);
        const fragmentation = data.data.map(row => row.fragmented_packets);

        const ctx = document.getElementById('problems-timeline-chart').getContext('2d');

        if (window.problemsTimelineChart) {
            window.problemsTimelineChart.destroy();
        }

        window.problemsTimelineChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Falhas de Conexão',
                    data: failures,
                    borderColor: '#ef4444',
                    backgroundColor: 'rgba(239, 68, 68, 0.1)',
                    fill: true,
                    tension: 0.4
                }, {
                    label: 'Pacotes Fragmentados',
                    data: fragmentation,
                    borderColor: '#f59e0b',
                    backgroundColor: 'rgba(245, 158, 11, 0.1)',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: true
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true
                    }
                }
            }
        });
    }
}

// Atualizar Health Score Chart
function updateHealthScoreChart() {
    const ctx = document.getElementById('health-score-chart').getContext('2d');

    if (window.healthScoreChart) {
        window.healthScoreChart.destroy();
    }

    const score = healthScore.total;
    const scoreColor = score >= 80 ? '#10b981' :
                      score >= 60 ? '#f59e0b' :
                      score >= 40 ? '#f97316' : '#ef4444';

    window.healthScoreChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: ['Score', 'Problemas'],
            datasets: [{
                data: [score, 100 - score],
                backgroundColor: [scoreColor, '#e5e7eb'],
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    enabled: false
                }
            },
            cutout: '75%'
        },
        plugins: [{
            beforeDraw: function(chart) {
                const width = chart.width;
                const height = chart.height;
                const ctx = chart.ctx;
                ctx.restore();
                const fontSize = (height / 114).toFixed(2);
                ctx.font = `bold ${fontSize}em sans-serif`;
                ctx.textBaseline = 'middle';
                ctx.fillStyle = scoreColor;
                const text = score.toFixed(0);
                const textX = Math.round((width - ctx.measureText(text).width) / 2);
                const textY = height / 2;
                ctx.fillText(text, textX, textY);
                ctx.save();
            }
        }]
    });
}

// Atualizar Resumo
function updateHealthSummary() {
    const score = healthScore.total;
    const overallStatus = score >= 80 ? '✅ Saudável' :
                         score >= 60 ? '⚠️ Degradada' :
                         score >= 40 ? '🔶 Problemática' : '🔴 Crítica';

    document.getElementById('overall-health').textContent = overallStatus;

    const criticalIssues = healthScore.issues.filter(i => i.includes('Blackhole') || i.includes('saturada')).length;
    const warnings = healthScore.issues.length - criticalIssues;

    document.getElementById('critical-issues').textContent = criticalIssues;
    document.getElementById('warnings').textContent = warnings;
}

// Atualizar tudo
async function refreshAll() {
    console.log('Atualizando diagnóstico de rede...');

    // Limpar alertas
    document.getElementById('health-alerts').innerHTML = '';
    resetHealthScore();

    await Promise.all([
        detectTrafficAsymmetry(),
        detectNetworkBlackholes(),
        detectPacketFragmentation(),
        detectTrafficConcentration(),
        analyzeInterfaceHealth(),
        detectConnectionFailures(),
        detectAnomalousProtocols(),
        analyzeProblematicASNs(),
        updateProblemsTimeline()
    ]);

    updateHealthSummary();
    updateHealthScoreChart();

    console.log(`Diagnóstico concluído! Health Score: ${healthScore.total}/100`);
}

// Inicializar
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Dashboard de Diagnóstico de Rede inicializado');
    loadSettings();
    await refreshAll();
    setInterval(refreshAll, config.refreshInterval);
});
