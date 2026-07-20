// Dashboard JavaScript - Akvorado

let config = {
    clickhouse: {
        host: '170.244.221.231:8123',
        user: 'akvorado',
        password: 'akvorado123',
        database: 'akvorado'
    },
    filters: {
        direction: 'both',  // input, output, both
        timeRange: 24  // horas
    },
    refreshInterval: 30000 // 30 segundos
};

// Obter direção do tráfego
function getTrafficDirection() {
    const select = document.getElementById('traffic-direction');
    if (select) {
        config.filters.direction = select.value;
    }
    return config.filters.direction;
}

// Obter intervalo de tempo
function getTimeRange() {
    const select = document.getElementById('time-range');
    if (select) {
        config.filters.timeRange = parseInt(select.value);
    }
    return config.filters.timeRange;
}

// Construir filtro WHERE baseado na direção
function buildDirectionFilter(tableAlias = '') {
    const direction = getTrafficDirection();
    const prefix = tableAlias ? tableAlias + '.' : '';

    if (direction === 'input') {
        // Tráfego de entrada: origem externa
        return `${prefix}InIfBoundary = 'external'`;
    } else if (direction === 'output') {
        // Tráfego de saída: destino externo
        return `${prefix}OutIfBoundary = 'external'`;
    }
    // both: sem filtro adicional
    return '1=1';
}

// Carregar configurações salvas
function loadSettings() {
    const savedHost = localStorage.getItem('clickhouse-host');
    const savedUser = localStorage.getItem('clickhouse-user');
    const savedPass = localStorage.getItem('clickhouse-pass');

    if (savedHost) {
        config.clickhouse.host = savedHost;
        document.getElementById('clickhouse-host').value = savedHost;
    }
    if (savedUser) {
        config.clickhouse.user = savedUser;
        document.getElementById('clickhouse-user').value = savedUser;
    }
    if (savedPass) {
        config.clickhouse.password = savedPass;
        document.getElementById('clickhouse-pass').value = savedPass;
    }
}

// Salvar configurações
function saveSettings() {
    const host = document.getElementById('clickhouse-host').value;
    const user = document.getElementById('clickhouse-user').value;
    const pass = document.getElementById('clickhouse-pass').value;

    config.clickhouse.host = host;
    config.clickhouse.user = user;
    config.clickhouse.password = pass;

    localStorage.setItem('clickhouse-host', host);
    localStorage.setItem('clickhouse-user', user);
    localStorage.setItem('clickhouse-pass', pass);

    alert('Configurações salvas! Atualizando dados...');
    refreshAll();
}

// Executar query no ClickHouse
async function executeQuery(query) {
    try {
        const url = `http://${config.clickhouse.host}/?database=${config.clickhouse.database}&user=${config.clickhouse.user}&password=${config.clickhouse.password}`;

        const response = await fetch(url, {
            method: 'POST',
            body: query,
            headers: {
                'Content-Type': 'text/plain'
            }
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

// Formatar bytes para formato legível
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

// Formatar números grandes
function formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(2) + 'K';
    return num.toString();
}

// Atualizar tráfego em tempo real
async function updateRealtimeTraffic() {
    const query = `
        SELECT
            count() as flows,
            sum(Bytes) as total_bytes,
            sum(Packets) as total_packets
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 5 MINUTE
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const stats = data.data[0];
        document.getElementById('active-flows').textContent = formatNumber(stats.flows);
        document.getElementById('total-bandwidth').textContent = formatBytes(stats.total_bytes);
        document.getElementById('packets-per-sec').textContent = formatNumber(Math.round(stats.total_packets / 300));
    }

    document.getElementById('last-update').textContent = new Date().toLocaleTimeString('pt-BR');
}

// Atualizar estatísticas gerais
async function updateGeneralStats() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            count() as total_flows,
            sum(Bytes) as total_bytes,
            uniq(SrcAddr) as unique_src_ips,
            uniq(DstAddr) as unique_dst_ips,
            uniq(SrcCountry) as unique_countries
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const stats = data.data[0];
        document.getElementById('total-flows-24h').textContent = formatNumber(stats.total_flows);
        document.getElementById('total-bytes-24h').textContent = formatBytes(stats.total_bytes);
        document.getElementById('unique-ips').textContent = formatNumber(stats.unique_src_ips + stats.unique_dst_ips);
        document.getElementById('unique-countries').textContent = formatNumber(stats.unique_countries || 0);
    }
}

// Atualizar Top Talkers
async function updateTopTalkers() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            sum(Bytes) as total_bytes,
            sum(Packets) as total_packets,
            count() as flow_count
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
        GROUP BY SrcAddr, DstAddr
        ORDER BY total_bytes DESC
        LIMIT 10
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#top-talkers-table tbody');
        tbody.innerHTML = '';

        data.data.forEach((row, index) => {
            const tr = document.createElement('tr');

            // Detectar tráfego suspeito (exemplo: tráfego muito alto)
            const isSuspicious = row.total_bytes > 1000000000; // > 1GB
            const status = isSuspicious ? '<span class="suspicious-indicator">⚠ SUSPEITO</span>' : '✓ Normal';

            tr.innerHTML = `
                <td>${index + 1}</td>
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${formatNumber(row.total_packets)}</td>
                <td>${formatNumber(row.flow_count)}</td>
                <td>${status}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Atualizar análise geográfica
async function updateGeoAnalysis() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            SrcCountry as country,
            count() as flow_count,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
          AND SrcCountry != ''
        GROUP BY country
        ORDER BY total_bytes DESC
        LIMIT 15
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#geo-table tbody');
        tbody.innerHTML = '';

        const totalBytes = data.data.reduce((sum, row) => sum + row.total_bytes, 0);

        data.data.forEach((row) => {
            const percentage = ((row.total_bytes / totalBytes) * 100).toFixed(2);
            const tr = document.createElement('tr');

            tr.innerHTML = `
                <td><span class="country-flag">${getCountryFlag(row.country)}</span>${row.country || 'Desconhecido'}</td>
                <td>${formatNumber(row.flow_count)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${percentage}%</td>
            `;
            tbody.appendChild(tr);
        });

        document.getElementById('unique-countries').textContent = data.data.length;
    }
}

// Obter bandeira do país (simulado)
function getCountryFlag(country) {
    const flags = {
        'BR': '🇧🇷', 'US': '🇺🇸', 'CN': '🇨🇳', 'RU': '🇷🇺',
        'DE': '🇩🇪', 'GB': '🇬🇧', 'FR': '🇫🇷', 'JP': '🇯🇵',
        'AR': '🇦🇷', 'CL': '🇨🇱', 'MX': '🇲🇽'
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
        '396982': 'Google Cloud',
        '54113': 'Fastly',
        '16625': 'Akamai',
        '22822': 'Limelight',

        // Provedores Brasileiros - Grandes Operadoras
        '28573': 'Claro/NET',
        '26599': 'TELEFÔNICA BRASIL',
        '7738': 'Telemar/Oi',
        '18881': 'TELEFÔNICA',
        '10429': 'TELEFÔNICA',
        '262589': 'ALGAR TELECOM',

        // Provedores Regionais Brasil
        '53062': 'BRISANET',
        '262582': 'DESKTEC',
        '262484': 'GRUPO CONECTA',
        '268370': 'SUMICITY',
        '263263': 'Gwtelecom',
        '268113': 'W5 Telecom',
        '28604': 'Tely Telecom',
        '262561': 'MHNET',
        '262634': 'VERO',
        '262973': 'UNIFIQUE',

        // Datacenters e Hosting
        '14061': 'DigitalOcean',
        '397213': 'Cloudflare',
        '209242': 'Cloudflare',
        '63949': 'Linode',
        '396982': 'Google Cloud',
        '19527': 'Google Cloud',
        '394425': 'Contabo',
        '8100': 'QuadraNet',
        '24940': 'Hetzner',
        '16276': 'OVH',
        '12876': 'Scaleway',

        // CDN e Edge
        '14618': 'Amazon CloudFront',
        '16625': 'Akamai CDN',
        '393406': 'Bunny CDN',
        '60068': 'CDN77',
        '209103': 'BelugaCDN',

        // Provedores Internacionais Populares
        '174': 'Cogent',
        '3356': 'Level3/Lumen',
        '1299': 'Telia',
        '3257': 'GTT',
        '6939': 'Hurricane Electric'
    };

    return asnNames[asn.toString()] || `AS${asn}`;
}

// Atualizar distribuição de protocolos
async function updateProtocolDistribution() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            Proto,
            count() as flow_count
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
        GROUP BY Proto
        ORDER BY flow_count DESC
        LIMIT 10
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const labels = data.data.map(row => getProtocolName(row.Proto));
        const values = data.data.map(row => row.flow_count);

        const ctx = document.getElementById('protocol-chart').getContext('2d');

        if (window.protocolChart) {
            window.protocolChart.destroy();
        }

        window.protocolChart = new Chart(ctx, {
            type: 'doughnut',
            data: {
                labels: labels,
                datasets: [{
                    data: values,
                    backgroundColor: [
                        '#667eea', '#764ba2', '#f093fb', '#4facfe',
                        '#43e97b', '#fa709a', '#fee140', '#30cfd0',
                        '#a8edea', '#fed6e3'
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
}

// Obter nome do protocolo
function getProtocolName(proto) {
    const protocols = {
        1: 'ICMP',
        6: 'TCP',
        17: 'UDP',
        47: 'GRE',
        50: 'ESP',
        51: 'AH',
        58: 'ICMPv6'
    };
    return protocols[proto] || `Protocolo ${proto}`;
}

// Atualizar top portas
async function updateTopPorts() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            DstPort as port,
            Proto as protocol,
            count() as flow_count
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
          AND DstPort > 0
        GROUP BY port, protocol
        ORDER BY flow_count DESC
        LIMIT 10
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#ports-table tbody');
        tbody.innerHTML = '';

        data.data.forEach((row) => {
            const tr = document.createElement('tr');
            const protocolClass = getProtocolClass(row.protocol);
            const protocolName = getProtocolName(row.protocol);

            tr.innerHTML = `
                <td><strong>${row.port}</strong> ${getPortName(row.port)}</td>
                <td><span class="protocol-badge ${protocolClass}">${protocolName}</span></td>
                <td>${formatNumber(row.flow_count)}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Obter classe CSS do protocolo
function getProtocolClass(proto) {
    if (proto === 6) return 'protocol-tcp';
    if (proto === 17) return 'protocol-udp';
    if (proto === 1) return 'protocol-icmp';
    return 'protocol-other';
}

// Obter nome da porta
function getPortName(port) {
    const ports = {
        80: '(HTTP)', 443: '(HTTPS)', 22: '(SSH)', 21: '(FTP)',
        25: '(SMTP)', 53: '(DNS)', 3306: '(MySQL)', 5432: '(PostgreSQL)',
        6379: '(Redis)', 27017: '(MongoDB)', 3389: '(RDP)',
        8080: '(HTTP-Alt)', 8443: '(HTTPS-Alt)'
    };
    return ports[port] || '';
}

// Atualizar tráfego suspeito
async function updateSuspiciousTraffic() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            SrcAddr,
            DstAddr,
            DstPort,
            Proto,
            count() as connection_attempts,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
          AND NOT (Proto = 17 AND (SrcPort = 443 OR DstPort = 443))
        GROUP BY SrcAddr, DstAddr, DstPort, Proto
        HAVING connection_attempts > 100 OR total_bytes > 1000000000
        ORDER BY connection_attempts DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#suspicious-table tbody');
        tbody.innerHTML = '';

        let alertCount = 0;

        data.data.forEach((row) => {
            const tr = document.createElement('tr');

            let threatType = '';
            let severity = '';
            let details = '';

            // Detectar tipo de ameaça
            if (row.connection_attempts > 500) {
                threatType = 'Port Scan';
                severity = '🔴 Alta';
                details = `${row.connection_attempts} tentativas de conexão`;
                alertCount++;
            } else if (row.total_bytes > 5000000000) {
                threatType = 'Data Exfiltration';
                severity = '🔴 Alta';
                details = `${formatBytes(row.total_bytes)} transferidos`;
                alertCount++;
            } else if (row.connection_attempts > 100) {
                threatType = 'Atividade Suspeita';
                severity = '🟡 Média';
                details = `${row.connection_attempts} conexões`;
            } else {
                threatType = 'Tráfego Alto';
                severity = '🟢 Baixa';
                details = `${formatBytes(row.total_bytes)} transferidos`;
            }

            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span> → <span class="ip-badge">${row.DstAddr}:${row.DstPort}</span></td>
                <td>${threatType}</td>
                <td>${details}</td>
                <td>${severity}</td>
            `;
            tbody.appendChild(tr);
        });

        // Atualizar alertas
        if (alertCount > 0) {
            document.getElementById('security-alerts').innerHTML = `
                <strong style="color: #ef4444;">${alertCount} alerta(s) de segurança detectado(s)!</strong>
                <br><small>Verifique a tabela abaixo para mais detalhes.</small>
            `;
        } else {
            document.getElementById('security-alerts').textContent = 'Nenhum alerta crítico detectado.';
        }
    } else {
        document.querySelector('#suspicious-table tbody').innerHTML =
            '<tr><td colspan="4" style="text-align: center; color: #10b981;">✓ Nenhuma atividade suspeita detectada</td></tr>';
        document.getElementById('security-alerts').textContent = 'Sistema seguro - nenhuma ameaça detectada.';
    }
}

// Atualizar timeline de tráfego
async function updateTrafficTimeline() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            toStartOfHour(TimeReceived) as hour,
            sum(Bytes) as total_bytes,
            count() as flow_count
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
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
        const bytes = data.data.map(row => row.total_bytes / (1024 * 1024)); // MB

        const ctx = document.getElementById('traffic-timeline-chart').getContext('2d');

        if (window.timelineChart) {
            window.timelineChart.destroy();
        }

        window.timelineChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Tráfego (MB)',
                    data: bytes,
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
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
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Megabytes (MB)'
                        }
                    }
                }
            }
        });
    }
}

// Análise detalhada de IPs mais ativos
async function updateActiveIPsDetail() {
    const hours = getTimeRange();
    const directionFilter = buildDirectionFilter();

    const query = `
        SELECT
            SrcAddr as ip,
            any(SrcCountry) as country,
            any(SrcAS) as asn,
            count() as total_flows,
            sum(Bytes) as total_bytes,
            uniq(DstPort) as unique_ports,
            uniq(DstAddr) as unique_destinations,
            groupArray(10)(DstPort) as top_ports,
            groupArray(5)(DstAddr) as top_destinations
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${directionFilter}
        GROUP BY ip
        ORDER BY total_flows DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#active-ips-detail-table tbody');
        tbody.innerHTML = '';

        data.data.forEach((row, index) => {
            const isSuspicious = (row.unique_ports > 100 || row.unique_destinations > 50);
            const topPorts = row.top_ports.slice(0, 5).join(', ');
            const topDests = row.top_destinations.slice(0, 3).map(ip => ip.substring(0, 15)).join(', ');
            const providerName = row.asn > 0 ? getASNName(row.asn) : '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${index + 1}</td>
                <td><span class="ip-badge">${row.ip}</span></td>
                <td>${row.country || '-'}</td>
                <td><span class="provider-name">${providerName}</span></td>
                <td>${formatNumber(row.total_flows)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${row.unique_ports}</td>
                <td>${row.unique_destinations}</td>
                <td style="font-size:0.85em;">${topPorts}</td>
                <td style="font-size:0.85em;">${topDests}</td>
                <td>${isSuspicious ? '<span class="danger">⚠ SUSPEITO</span>' : '<span class="safe">✓ Normal</span>'}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Análise de tráfego QUIC
async function updateQUICAnalysis() {
    const hours = getTimeRange();

    const statsQuery = `
        SELECT
            count() as total_flows,
            sum(Bytes) as total_bytes,
            uniq(SrcAddr) + uniq(DstAddr) as unique_ips
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND Proto = 17
          AND (SrcPort = 443 OR DstPort = 443)
        FORMAT JSON
    `;

    const statsData = await executeQuery(statsQuery);

    if (statsData && statsData.data && statsData.data.length > 0) {
        const stats = statsData.data[0];
        document.getElementById('quic-total-flows').textContent = formatNumber(stats.total_flows);
        document.getElementById('quic-total-bytes').textContent = formatBytes(stats.total_bytes);
        document.getElementById('quic-unique-ips').textContent = formatNumber(stats.unique_ips);
    }

    const detailQuery = `
        SELECT
            SrcAddr,
            DstAddr,
            any(SrcCountry) as country,
            any(SrcAS) as asn,
            count() as flows,
            sum(Bytes) as bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND Proto = 17
          AND (SrcPort = 443 OR DstPort = 443)
        GROUP BY SrcAddr, DstAddr
        ORDER BY flows DESC
        LIMIT 20
        FORMAT JSON
    `;

    const detailData = await executeQuery(detailQuery);

    if (detailData && detailData.data) {
        const tbody = document.querySelector('#quic-table tbody');
        tbody.innerHTML = '';

        detailData.data.forEach(row => {
            const provider = row.asn > 0 ? getASNName(row.asn) : '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.SrcAddr}</span></td>
                <td><span class="ip-badge">${row.DstAddr}</span></td>
                <td>${row.country || '-'}</td>
                <td><span class="asn-badge">AS${row.asn}</span></td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatBytes(row.bytes)}</td>
                <td><span class="provider-name">${provider}</span></td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Atualizar todos os painéis
async function refreshAll() {
    console.log('Atualizando todos os painéis...');

    await Promise.all([
        updateRealtimeTraffic(),
        updateGeneralStats(),
        updateTopTalkers(),
        updateGeoAnalysis(),
        updateProtocolDistribution(),
        updateTopPorts(),
        updateSuspiciousTraffic(),
        updateTrafficTimeline(),
        updateActiveIPsDetail(),
        updateQUICAnalysis()
    ]);

    console.log('Atualização concluída!');
}

// Inicializar dashboard
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Dashboard inicializado');
    loadSettings();
    await refreshAll();

    // Auto-refresh a cada intervalo definido
    setInterval(refreshAll, config.refreshInterval);
});
