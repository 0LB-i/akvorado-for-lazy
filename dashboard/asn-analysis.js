// ASN Analysis Dashboard JavaScript

let config = {
    clickhouse: {
        host: '170.244.221.231:8123',
        user: 'akvorado',
        password: 'akvorado123',
        database: 'akvorado'
    },
    filters: {
        direction: 'incoming',  // incoming, outgoing, both
        timeRange: 24  // horas
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

// Obter campo ASN baseado na direção
function getASNField() {
    const direction = document.getElementById('direction-filter').value;
    config.filters.direction = direction;

    if (direction === 'incoming') return 'SrcAS';
    if (direction === 'outgoing') return 'DstAS';
    return 'SrcAS';  // padrão
}

// Obter intervalo de tempo
function getTimeInterval() {
    const hours = parseInt(document.getElementById('time-range').value);
    config.filters.timeRange = hours;
    return hours;
}

// Atualizar resumo ASN
async function updateASNSummary() {
    const asnField = getASNField();
    const hours = getTimeInterval();

    const query = `
        SELECT
            uniq(${asnField}) as unique_asns,
            count() as total_flows,
            sum(Bytes) as total_bytes,
            uniq(SrcAddr) + uniq(DstAddr) as unique_ips
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const stats = data.data[0];
        document.getElementById('unique-asns').textContent = formatNumber(stats.unique_asns);
        document.getElementById('total-flows').textContent = formatNumber(stats.total_flows);
        document.getElementById('total-bytes').textContent = formatBytes(stats.total_bytes);
        document.getElementById('unique-ips').textContent = formatNumber(stats.unique_ips);
    }
}

// Top ASNs gráfico
async function updateASNTrafficChart() {
    const asnField = getASNField();
    const hours = getTimeInterval();

    const query = `
        SELECT
            ${asnField} as asn,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        GROUP BY asn
        ORDER BY total_bytes DESC
        LIMIT 10
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const labels = data.data.map(row => `AS${row.asn}`);
        const values = data.data.map(row => row.total_bytes / (1024 * 1024 * 1024)); // GB

        const ctx = document.getElementById('asn-traffic-chart').getContext('2d');

        if (window.asnChart) {
            window.asnChart.destroy();
        }

        window.asnChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [{
                    label: 'Tráfego (GB)',
                    data: values,
                    backgroundColor: '#667eea',
                    borderColor: '#5568d3',
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Gigabytes (GB)'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    }
}

// Top ASNs detalhado
async function updateASNDetailTable() {
    const asnField = getASNField();
    const hours = getTimeInterval();
    const direction = document.getElementById('direction-filter').value;

    // Escolher campo de país baseado na direção
    const countryField = direction === 'incoming' ? 'SrcCountry' :
                         direction === 'outgoing' ? 'DstCountry' : 'SrcCountry';

    const query = `
        SELECT
            ${asnField} as asn,
            any(${countryField}) as country,
            count() as flows,
            sum(Bytes) as total_bytes,
            uniq(SrcAddr) + uniq(DstAddr) as unique_ips
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        GROUP BY asn
        ORDER BY total_bytes DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#asn-detail-table tbody');
        tbody.innerHTML = '';

        const totalBytes = data.data.reduce((sum, row) => sum + row.total_bytes, 0);

        data.data.forEach((row, index) => {
            const percentage = ((row.total_bytes / totalBytes) * 100).toFixed(2);
            const providerName = getASNName(row.asn);
            const countryDisplay = row.country ?
                `<span class="country-flag">${getCountryFlag(row.country)}</span>${row.country}` :
                '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${index + 1}</td>
                <td><span class="asn-badge">AS${row.asn}</span></td>
                <td class="provider-name">${providerName}</td>
                <td>${countryDisplay}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${formatNumber(row.unique_ips)}</td>
                <td>${percentage}%</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Detectar ASNs suspeitos
async function detectSuspiciousASNs() {
    const asnField = getASNField();
    const hours = getTimeInterval();
    const direction = document.getElementById('direction-filter').value;
    const countryField = direction === 'incoming' ? 'SrcCountry' :
                         direction === 'outgoing' ? 'DstCountry' : 'SrcCountry';

    const query = `
        SELECT
            ${asnField} as asn,
            any(${countryField}) as country,
            uniq(DstPort) as unique_ports,
            uniq(DstAddr) as unique_targets,
            count() as attempts,
            CASE
                WHEN uniq(DstPort) > 100 THEN 'Port Scanning'
                WHEN uniq(DstAddr) > 50 THEN 'Network Scanning'
                WHEN count() > 10000 THEN 'High Volume Attack'
                ELSE 'Suspicious Activity'
            END as threat_type
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        GROUP BY asn
        HAVING unique_ports > 50 OR unique_targets > 30 OR attempts > 5000
        ORDER BY attempts DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#suspicious-asn-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            let severity = '🟢 Baixo';

            if (row.attempts > 50000 || row.unique_ports > 200) severity = '🔴 Crítico';
            else if (row.attempts > 20000 || row.unique_ports > 100) severity = '🟡 Alto';
            else if (row.attempts > 10000 || row.unique_ports > 50) severity = '🟠 Médio';

            const providerName = getASNName(row.asn);
            const countryDisplay = row.country ?
                `<span class="country-flag">${getCountryFlag(row.country)}</span>${row.country}` :
                '-';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="asn-badge">AS${row.asn}</span></td>
                <td class="provider-name">${providerName}</td>
                <td>${countryDisplay}</td>
                <td class="danger">${row.threat_type}</td>
                <td>${formatNumber(row.unique_targets)}</td>
                <td class="danger">${formatNumber(row.attempts)}</td>
                <td>${severity}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#suspicious-asn-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhuma atividade suspeita detectada</td></tr>';
    }
}

// Timeline de tráfego por ASN
async function updateASNTimeline() {
    const asnField = getASNField();
    const hours = getTimeInterval();

    // Primeiro, pegar os top 5 ASNs
    const topQuery = `
        SELECT ${asnField} as asn
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        GROUP BY asn
        ORDER BY sum(Bytes) DESC
        LIMIT 5
        FORMAT JSON
    `;

    const topData = await executeQuery(topQuery);

    if (!topData || !topData.data) return;

    const topASNs = topData.data.map(row => row.asn);

    // Agora pegar dados ao longo do tempo
    const timelineQuery = `
        SELECT
            toStartOfHour(TimeReceived) as hour,
            ${asnField} as asn,
            sum(Bytes) / (1024 * 1024 * 1024) as gb
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} IN (${topASNs.join(',')})
        GROUP BY hour, asn
        ORDER BY hour, asn
        FORMAT JSON
    `;

    const data = await executeQuery(timelineQuery);

    if (data && data.data) {
        // Preparar dados para o gráfico
        const hours_list = [...new Set(data.data.map(row => row.hour))].sort();
        const datasets = [];

        const colors = ['#667eea', '#f093fb', '#4facfe', '#43e97b', '#fa709a'];

        topASNs.forEach((asn, index) => {
            const asnData = hours_list.map(hour => {
                const found = data.data.find(row => row.hour === hour && row.asn === asn);
                return found ? found.gb : 0;
            });

            datasets.push({
                label: `AS${asn}`,
                data: asnData,
                borderColor: colors[index],
                backgroundColor: colors[index] + '33',
                fill: false,
                tension: 0.4
            });
        });

        const labels = hours_list.map(hour => {
            const date = new Date(hour);
            return date.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
        });

        const ctx = document.getElementById('asn-timeline-chart').getContext('2d');

        if (window.timelineChart) {
            window.timelineChart.destroy();
        }

        window.timelineChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: labels,
                datasets: datasets
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Gigabytes (GB)'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: true,
                        position: 'top'
                    }
                }
            }
        });
    }
}

// Distribuição geográfica por ASN
async function updateASNCountryDistribution() {
    const asnField = getASNField();
    const hours = getTimeInterval();

    const query = `
        SELECT
            SrcCountry as country,
            uniq(${asnField}) as unique_asns,
            count() as flows,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
          AND length(SrcCountry) > 0
        GROUP BY country
        ORDER BY total_bytes DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#asn-country-table tbody');
        tbody.innerHTML = '';

        const totalBytes = data.data.reduce((sum, row) => sum + row.total_bytes, 0);

        data.data.forEach(row => {
            const percentage = ((row.total_bytes / totalBytes) * 100).toFixed(2);

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="country-flag">${getCountryFlag(row.country)}</span>${row.country || 'Desconhecido'}</td>
                <td>${row.unique_asns}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${percentage}%</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// IPs mais ativos por ASN
async function updateASNTopIPs() {
    const asnField = getASNField();
    const hours = getTimeInterval();

    const query = `
        SELECT
            ${asnField} as asn,
            SrcAddr as ip,
            count() as flows,
            sum(Bytes) as total_bytes,
            uniq(DstPort) as unique_ports
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL ${hours} HOUR
          AND ${asnField} > 0
        GROUP BY asn, ip
        ORDER BY flows DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#asn-ips-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const isSuspicious = row.unique_ports > 50 || row.flows > 10000;
            const providerName = getASNName(row.asn);

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="asn-badge">AS${row.asn}</span></td>
                <td><span class="ip-badge">${row.ip}</span></td>
                <td class="provider-name">${providerName}</td>
                <td>${formatNumber(row.flows)}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${row.unique_ports}</td>
                <td>${isSuspicious ? '<span class="danger">⚠️ SUSPEITO</span>' : '<span class="safe">✓ Normal</span>'}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Obter bandeira do país
function getCountryFlag(country) {
    const flags = {
        'BR': '🇧🇷', 'US': '🇺🇸', 'CN': '🇨🇳', 'RU': '🇷🇺',
        'DE': '🇩🇪', 'GB': '🇬🇧', 'FR': '🇫🇷', 'JP': '🇯🇵',
        'AR': '🇦🇷', 'CL': '🇨🇱', 'MX': '🇲🇽', 'ES': '🇪🇸',
        'IT': '🇮🇹', 'CA': '🇨🇦', 'AU': '🇦🇺', 'IN': '🇮🇳'
    };
    return flags[country] || '🌐';
}

// Obter nome do provedor por ASN
function getASNName(asn) {
    const asnNames = {
        // Grandes provedores globais
        '15169': 'Google LLC',
        '16509': 'Amazon AWS',
        '13335': 'Cloudflare',
        '8075': 'Microsoft',
        '32934': 'Facebook/Meta',
        '714': 'Apple',
        '20940': 'Akamai',
        '2906': 'Netflix',

        // Brasil - Grandes operadoras
        '28573': 'Claro/NET',
        '26599': 'TELEFÔNICA BRASIL',
        '7738': 'Telemar/Oi',
        '18881': 'TELEFÔNICA BRASIL',
        '27699': 'TELEFÔNICA BRASIL',
        '10429': 'TELEFÔNICA BRASIL',
        '263263': 'Gwtelecom',

        // Brasil - ISPs regionais
        '53062': 'BRISANET',
        '28573': 'Claro S.A',
        '262287': 'MaxxLink',
        '264566': 'Digibrás',
        '269141': 'AKINET',
        '396982': 'Google Cloud',
        '28338': 'CLARO NXT',
        '53240': 'COPREL',
        '54113': 'FASTNET',
        '264979': 'Veloo Telecom',
        '268113': 'W5 Telecom',
        '28604': 'Tely Telecom',

        // Internacional
        '3356': 'Level3/Lumen',
        '1299': 'Telia',
        '6762': 'Telecom Italia',
        '12956': 'Telefonica',
        '3320': 'Deutsche Telekom',
        '5511': 'Orange France'
    };

    return asnNames[asn.toString()] || `AS${asn}`;
}

// Atualizar tudo
async function refreshAll() {
    console.log('Atualizando análise ASN...');

    await Promise.all([
        updateASNSummary(),
        updateASNTrafficChart(),
        updateASNDetailTable(),
        detectSuspiciousASNs(),
        updateASNTimeline(),
        updateASNCountryDistribution(),
        updateASNTopIPs()
    ]);

    console.log('Atualização concluída!');
}

// Inicializar
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Dashboard ASN inicializado');
    loadSettings();
    await refreshAll();
    setInterval(refreshAll, config.refreshInterval);
});
