// Attack Analysis Dashboard JavaScript

let config = {
    clickhouse: {
        host: '170.244.221.231:8123',
        user: 'akvorado',
        password: 'akvorado123',
        database: 'akvorado'
    },
    thresholds: {
        ddos: {
            flowsPerSecond: 100,
            bytesPerSecond: 100000000, // 100 MB/s
            packetsPerSecond: 10000
        },
        portScan: {
            uniquePorts: 20,
            uniqueTargets: 10
        },
        bruteForce: {
            attempts: 50
        },
        trafficSpike: {
            variationPercent: 300 // 300% de aumento
        }
    },
    refreshInterval: 30000
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

// Obter filtro de severidade
function getSeverityFilter() {
    const select = document.getElementById('severity-filter');
    return select ? select.value : 'all';
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
        // Provedores Globais
        '15169': 'Google LLC',
        '16509': 'Amazon AWS',
        '13335': 'Cloudflare',
        '8075': 'Microsoft',
        '32934': 'Facebook/Meta',
        '714': 'Apple',
        '20940': 'Akamai',
        '2906': 'Netflix',

        // Provedores Brasileiros
        '28573': 'Claro/NET',
        '26599': 'TELEFÔNICA BRASIL',
        '7738': 'Telemar/Oi',
        '263263': 'Gwtelecom',
        '53062': 'BRISANET',
        '268113': 'W5 Telecom',
        '28604': 'Tely Telecom',

        // Datacenters
        '14061': 'DigitalOcean',
        '63949': 'Linode',
        '24940': 'Hetzner',
        '16276': 'OVH',

        // Outros
        '174': 'Cogent',
        '3356': 'Level3/Lumen',
        '6939': 'Hurricane Electric'
    };

    return asnNames[asn.toString()] || `AS${asn}`;
}

// Determinar severidade
function getSeverity(type, metrics) {
    if (type === 'ddos') {
        if (metrics.flows > 10000 || metrics.bytes > 1000000000) return 'critical';
        if (metrics.flows > 5000 || metrics.bytes > 500000000) return 'high';
        if (metrics.flows > 1000) return 'medium';
        return 'low';
    } else if (type === 'portscan') {
        if (metrics.ports > 1000) return 'critical';
        if (metrics.ports > 500) return 'high';
        if (metrics.ports > 100) return 'medium';
        return 'low';
    } else if (type === 'bruteforce') {
        if (metrics.attempts > 1000) return 'critical';
        if (metrics.attempts > 500) return 'high';
        if (metrics.attempts > 100) return 'medium';
        return 'low';
    } else if (type === 'spike') {
        if (metrics.variation > 1000) return 'critical';
        if (metrics.variation > 500) return 'high';
        if (metrics.variation > 300) return 'medium';
        return 'low';
    }
    return 'low';
}

// Formatar severidade
function formatSeverity(severity) {
    const severities = {
        'critical': '🔴 Crítico',
        'high': '🟠 Alto',
        'medium': '🟡 Médio',
        'low': '🟢 Baixo'
    };
    return severities[severity] || severity;
}

// Atualizar resumo de ataques
async function updateAttackSummary() {
    const hours = getTimeRange();

    const query = `
        SELECT
            count() as total_attacks,
            uniq(SrcAddr) as unique_attackers,
            uniq(DstAddr) as unique_targets
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND (
              (count() OVER (PARTITION BY SrcAddr) > 100)
              OR (uniq(DstPort) OVER (PARTITION BY SrcAddr) > 20)
              OR (DstPort IN (22, 23, 3389, 21, 3306, 1433, 5432) AND count() OVER (PARTITION BY SrcAddr, DstAddr, DstPort) > 50)
          )
        FORMAT JSON
    `;

    // Query simplificada para resumo
    const simpleQuery = `
        SELECT
            count(DISTINCT SrcAddr) as unique_attackers,
            count(DISTINCT DstAddr) as unique_targets
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        FORMAT JSON
    `;

    const data = await executeQuery(simpleQuery);

    if (data && data.data && data.data.length > 0) {
        const stats = data.data[0];
        document.getElementById('unique-attackers').textContent = formatNumber(stats.unique_attackers);
        document.getElementById('unique-targets').textContent = formatNumber(stats.unique_targets);
    }
}

// Detectar ataques DDoS
async function detectDDoSAttacks() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            any(SrcCountry) as country,
            any(SrcAS) as asn,
            count() as flows,
            sum(Bytes) as total_bytes,
            sum(Packets) as total_packets
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        GROUP BY SrcAddr, DstAddr
        HAVING flows > ${config.thresholds.ddos.flowsPerSecond * 60}
            OR total_bytes > ${config.thresholds.ddos.bytesPerSecond * 60}
            OR total_packets > ${config.thresholds.ddos.packetsPerSecond * 60}
        ORDER BY flows DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#ddos-table tbody');
        tbody.innerHTML = '';

        let criticalCount = 0;

        data.data.forEach(row => {
            const severity = getSeverity('ddos', { flows: row.flows, bytes: row.total_bytes });
            if (severity === 'critical') criticalCount++;

            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatNumber(row.total_packets)}</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });

        document.getElementById('total-attacks').textContent = data.data.length;
        document.getElementById('critical-attacks').textContent = criticalCount;

        if (criticalCount > 0) {
            showAlert('critical', `${criticalCount} ataque(s) DDoS crítico(s) detectado(s)!`);
        }
    } else {
        document.querySelector('#ddos-table tbody').innerHTML =
            '<tr><td colspan="8" style="text-align: center; color: #10b981;">✓ Nenhum ataque DDoS detectado</td></tr>';
        document.getElementById('total-attacks').textContent = '0';
        document.getElementById('critical-attacks').textContent = '0';
    }
}

// Detectar Port Scanning
async function detectPortScanning() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            any(SrcCountry) as country,
            any(SrcAS) as asn,
            uniq(DstAddr) as unique_targets,
            uniq(DstPort) as unique_ports,
            count() as attempts
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        GROUP BY SrcAddr
        HAVING unique_ports > ${config.thresholds.portScan.uniquePorts}
           OR unique_targets > ${config.thresholds.portScan.uniqueTargets}
        ORDER BY unique_ports DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#port-scan-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = getSeverity('portscan', { ports: row.unique_ports });
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${row.unique_targets}</td>
                <td class="critical">${row.unique_ports}</td>
                <td>${formatNumber(row.attempts)}</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#port-scan-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum port scanning detectado</td></tr>';
    }
}

// Detectar Brute Force
async function detectBruteForce() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            DstPort,
            count() as attempts,
            min(TimeReceived) as start_time,
            max(TimeReceived) as end_time,
            CASE
                WHEN DstPort = 22 THEN 'SSH'
                WHEN DstPort = 23 THEN 'Telnet'
                WHEN DstPort = 3389 THEN 'RDP'
                WHEN DstPort = 21 THEN 'FTP'
                WHEN DstPort = 3306 THEN 'MySQL'
                WHEN DstPort = 1433 THEN 'MSSQL'
                WHEN DstPort = 5432 THEN 'PostgreSQL'
                ELSE 'Unknown'
            END as service
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND DstPort IN (22, 23, 3389, 21, 3306, 1433, 5432)
        GROUP BY SrcAddr, DstAddr, DstPort
        HAVING attempts > ${config.thresholds.bruteForce.attempts}
        ORDER BY attempts DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#bruteforce-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = getSeverity('bruteforce', { attempts: row.attempts });
            const duration = Math.round((new Date(row.end_time) - new Date(row.start_time)) / 1000 / 60);

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.DstPort}</td>
                <td><span class="attack-badge attack-bruteforce">${row.service}</span></td>
                <td class="critical">${formatNumber(row.attempts)}</td>
                <td>${duration} min</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#bruteforce-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum brute force detectado</td></tr>';
    }
}

// Detectar Flood Attacks
async function detectFloodAttacks() {
    const hours = getTimeRange();

    const query = `
        SELECT
            CASE
                WHEN Proto = 6 THEN 'SYN Flood'
                WHEN Proto = 17 THEN 'UDP Flood'
                ELSE 'Other'
            END as attack_type,
            SrcAddr,
            DstAddr,
            Proto,
            count() / ${hours * 3600} as packets_per_second,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
        GROUP BY SrcAddr, DstAddr, Proto
        HAVING packets_per_second > 100
        ORDER BY packets_per_second DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#flood-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = row.packets_per_second > 10000 ? 'critical' :
                           row.packets_per_second > 5000 ? 'high' :
                           row.packets_per_second > 1000 ? 'medium' : 'low';

            const protoName = row.Proto === 6 ? 'TCP' : row.Proto === 17 ? 'UDP' : `Proto ${row.Proto}`;

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="attack-badge attack-flood">${row.attack_type}</span></td>
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${protoName}</td>
                <td class="critical">${formatNumber(Math.round(row.packets_per_second))}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#flood-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum flood attack detectado</td></tr>';
    }
}

// Detectar Picos de Tráfego
async function detectTrafficSpikes() {
    const hours = getTimeRange();

    const query = `
        WITH hourly_stats AS (
            SELECT
                toStartOfHour(TimeReceived) as hour,
                SrcAddr,
                sum(Bytes) as bytes,
                count() as flows
            FROM akvorado.flows
            WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
            GROUP BY hour, SrcAddr
        ),
        avg_stats AS (
            SELECT
                SrcAddr,
                avg(bytes) as avg_bytes,
                avg(flows) as avg_flows
            FROM hourly_stats
            GROUP BY SrcAddr
        )
        SELECT
            h.hour,
            h.SrcAddr,
            any(f.SrcCountry) as country,
            any(f.SrcAS) as asn,
            h.bytes,
            h.flows,
            (h.bytes / a.avg_bytes * 100 - 100) as variation_percent
        FROM hourly_stats h
        JOIN avg_stats a ON h.SrcAddr = a.SrcAddr
        JOIN akvorado.flows f ON h.SrcAddr = f.SrcAddr
        WHERE h.bytes > a.avg_bytes * 3
        GROUP BY h.hour, h.SrcAddr, h.bytes, h.flows, a.avg_bytes
        ORDER BY variation_percent DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#traffic-spikes-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = getSeverity('spike', { variation: row.variation_percent });
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';
            const timestamp = new Date(row.hour).toLocaleString('pt-BR');

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${timestamp}</td>
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td>${row.country ? getCountryFlag(row.country) + ' ' + row.country : '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${formatBytes(row.bytes)}</td>
                <td>${formatNumber(row.flows)}</td>
                <td class="critical">+${Math.round(row.variation_percent)}%</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#traffic-spikes-table tbody').innerHTML =
            '<tr><td colspan="8" style="text-align: center; color: #10b981;">✓ Nenhum pico de tráfego detectado</td></tr>';
    }
}

// Analisar IPs da Gwtelecom (AS263263)
async function analyzeGwtelecomAttacks() {
    const hours = getTimeRange();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            any(DstCountry) as target_country,
            DstPort,
            count() as attempts,
            sum(Bytes) as total_bytes,
            CASE
                WHEN DstPort = 22 THEN 'SSH Brute Force'
                WHEN DstPort = 23 THEN 'Telnet Attack'
                WHEN DstPort = 3389 THEN 'RDP Attack'
                WHEN DstPort = 21 THEN 'FTP Attack'
                WHEN DstPort = 3306 THEN 'MySQL Attack'
                WHEN DstPort = 1433 THEN 'MSSQL Attack'
                WHEN uniq(DstPort) > 50 THEN 'Port Scanning'
                ELSE 'Suspicious Traffic'
            END as attack_type
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND SrcAS = 263263
          AND OutIfBoundary = 'external'
        GROUP BY SrcAddr, DstAddr, DstPort
        HAVING attempts > 50
        ORDER BY attempts DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#gwtelecom-attacks-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const severity = row.attempts > 1000 ? 'critical' :
                           row.attempts > 500 ? 'high' :
                           row.attempts > 100 ? 'medium' : 'low';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.target_country ? getCountryFlag(row.target_country) + ' ' + row.target_country : '-'}</td>
                <td><span class="attack-badge attack-bruteforce">${row.attack_type}</span></td>
                <td class="critical">${formatNumber(row.attempts)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td class="${severity}">${formatSeverity(severity)}</td>
            `;
            tbody.appendChild(tr);
        });

        if (data.data.length > 0) {
            showAlert('warning', `${data.data.length} IP(s) da Gwtelecom gerando tráfego suspeito!`);
        }
    } else {
        document.querySelector('#gwtelecom-attacks-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum tráfego suspeito da Gwtelecom detectado</td></tr>';
    }
}

// Mostrar alerta
function showAlert(type, message) {
    const alertsDiv = document.getElementById('security-alerts');
    const alertClass = type === 'critical' ? 'alert-critical' :
                      type === 'warning' ? 'alert-warning' : 'alert-info';

    const alert = document.createElement('div');
    alert.className = `alert-box ${alertClass}`;
    alert.innerHTML = `<strong>${message}</strong>`;
    alertsDiv.appendChild(alert);
}

// Atualizar gráfico de tipos de ataques
async function updateAttackTypesChart() {
    // Dados simulados - você pode integrar com queries reais
    const attackTypes = ['DDoS', 'Port Scan', 'Brute Force', 'Flood', 'Web Attack'];
    const attackCounts = [12, 25, 18, 8, 5];

    const ctx = document.getElementById('attack-types-chart').getContext('2d');

    if (window.attackTypesChart) {
        window.attackTypesChart.destroy();
    }

    window.attackTypesChart = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: attackTypes,
            datasets: [{
                data: attackCounts,
                backgroundColor: [
                    '#dc2626',
                    '#ea580c',
                    '#f59e0b',
                    '#8b5cf6',
                    '#ec4899'
                ]
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom'
                }
            }
        }
    });
}

// Atualizar timeline de ataques
async function updateAttacksTimeline() {
    const hours = getTimeRange();

    const query = `
        SELECT
            toStartOfHour(TimeReceived) as hour,
            count() as attack_count
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
        const counts = data.data.map(row => row.attack_count);

        const ctx = document.getElementById('attacks-timeline-chart').getContext('2d');

        if (window.attacksTimelineChart) {
            window.attacksTimelineChart.destroy();
        }

        window.attacksTimelineChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Ataques Detectados',
                    data: counts,
                    borderColor: '#dc2626',
                    backgroundColor: 'rgba(220, 38, 38, 0.1)',
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

// Atualizar tudo
async function refreshAll() {
    console.log('Atualizando análise de ataques...');

    // Limpar alertas antigos
    document.getElementById('security-alerts').innerHTML = '';

    await Promise.all([
        updateAttackSummary(),
        detectDDoSAttacks(),
        detectPortScanning(),
        detectBruteForce(),
        detectFloodAttacks(),
        detectTrafficSpikes(),
        analyzeGwtelecomAttacks(),
        updateAttackTypesChart(),
        updateAttacksTimeline()
    ]);

    console.log('Atualização concluída!');
}

// Inicializar
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Dashboard de Análise de Ataques inicializado');
    loadSettings();
    await refreshAll();
    setInterval(refreshAll, config.refreshInterval);
});
