// CGNAT Analysis Dashboard JavaScript

let config = {
    clickhouse: {
        host: '170.244.221.231:8123',
        user: 'akvorado',
        password: 'akvorado123',
        database: 'akvorado'
    },
    cgnat: {
        ips: ['200.1.1.1', '200.1.1.2'],
        portRangeSize: 1000
    },
    refreshInterval: 30000
};

// Carregar configurações
function loadSettings() {
    const savedHost = localStorage.getItem('clickhouse-host');
    const savedUser = localStorage.getItem('clickhouse-user');
    const savedPass = localStorage.getItem('clickhouse-pass');
    const savedCGNATIPs = localStorage.getItem('cgnat-ips');
    const savedPortRange = localStorage.getItem('port-range-size');

    if (savedHost) config.clickhouse.host = savedHost;
    if (savedUser) config.clickhouse.user = savedUser;
    if (savedPass) config.clickhouse.password = savedPass;

    if (savedCGNATIPs) {
        config.cgnat.ips = savedCGNATIPs.split(',').map(ip => ip.trim());
        document.getElementById('cgnat-ips').value = savedCGNATIPs;
    }

    if (savedPortRange) {
        config.cgnat.portRangeSize = parseInt(savedPortRange);
        document.getElementById('port-range-size').value = savedPortRange;
    }
}

// Salvar configurações
function saveSettings() {
    const cgnatIPs = document.getElementById('cgnat-ips').value;
    const portRange = document.getElementById('port-range-size').value;

    config.cgnat.ips = cgnatIPs.split(',').map(ip => ip.trim());
    config.cgnat.portRangeSize = parseInt(portRange);

    localStorage.setItem('cgnat-ips', cgnatIPs);
    localStorage.setItem('port-range-size', portRange);

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

// Atualizar resumo CGNAT
async function updateCGNATSummary() {
    const ipsList = config.cgnat.ips.map(ip => `'${ip}'`).join(',');

    const query = `
        SELECT
            uniq(SrcAddr) as unique_ips,
            uniq(floor(SrcPort / ${config.cgnat.portRangeSize})) as active_ranges,
            count() as total_flows
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 1 HOUR
          AND SrcAddr IN (${ipsList})
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const stats = data.data[0];
        document.getElementById('total-cgnat-ips').textContent = stats.unique_ips;
        document.getElementById('active-ranges').textContent = formatNumber(stats.active_ranges);
        document.getElementById('total-cgnat-flows').textContent = formatNumber(stats.total_flows);
    }
}

// Atualizar atividade por range
async function updatePortRangeActivity() {
    const ipsList = config.cgnat.ips.map(ip => `'${ip}'`).join(',');

    const query = `
        SELECT
            SrcAddr as ip,
            floor(SrcPort / ${config.cgnat.portRangeSize}) * ${config.cgnat.portRangeSize} as range_start,
            count() as flows,
            uniq(DstAddr) as unique_targets,
            uniq(DstPort) as unique_ports,
            sum(Bytes) as total_bytes
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 1 HOUR
          AND SrcAddr IN (${ipsList})
        GROUP BY ip, range_start
        ORDER BY flows DESC
        LIMIT 50
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#port-range-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const rangeEnd = row.range_start + config.cgnat.portRangeSize - 1;
            const isSuspicious = row.unique_ports > 50 || row.unique_targets > 30;

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.ip}</span></td>
                <td><span class="port-range">${row.range_start}-${rangeEnd}</span></td>
                <td>${formatNumber(row.flows)}</td>
                <td>${row.unique_targets}</td>
                <td>${row.unique_ports}</td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${isSuspicious ? '<span class="danger">⚠️ SUSPEITO</span>' : '<span class="safe">✓ Normal</span>'}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Detectar port scanning
async function detectPortScanning() {
    const ipsList = config.cgnat.ips.map(ip => `'${ip}'`).join(',');

    const query = `
        SELECT
            SrcAddr as ip,
            SrcPort,
            floor(SrcPort / ${config.cgnat.portRangeSize}) * ${config.cgnat.portRangeSize} as range_start,
            uniq(DstPort) as ports_scanned,
            uniq(DstAddr) as targets,
            count() as attempts
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 1 HOUR
          AND SrcAddr IN (${ipsList})
        GROUP BY ip, SrcPort, range_start
        HAVING ports_scanned > 20
        ORDER BY ports_scanned DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#port-scan-table tbody');
        tbody.innerHTML = '';

        data.data.forEach(row => {
            const rangeEnd = row.range_start + config.cgnat.portRangeSize - 1;
            let severity = '🟢 Baixo';

            if (row.ports_scanned > 100) severity = '🔴 Crítico';
            else if (row.ports_scanned > 50) severity = '🟡 Alto';
            else if (row.ports_scanned > 30) severity = '🟠 Médio';

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.ip}</span></td>
                <td>${row.SrcPort}</td>
                <td><span class="port-range">${row.range_start}-${rangeEnd}</span></td>
                <td class="danger">${row.ports_scanned}</td>
                <td>${row.targets}</td>
                <td>${formatNumber(row.attempts)}</td>
                <td>${severity}</td>
            `;
            tbody.appendChild(tr);
        });
    } else {
        document.querySelector('#port-scan-table tbody').innerHTML =
            '<tr><td colspan="7" style="text-align: center; color: #10b981;">✓ Nenhum port scanning detectado</td></tr>';
    }
}

// Detectar ataques
async function detectAttacks() {
    const ipsList = config.cgnat.ips.map(ip => `'${ip}'`).join(',');

    const query = `
        SELECT
            SrcAddr as ip,
            SrcPort,
            floor(SrcPort / ${config.cgnat.portRangeSize}) * ${config.cgnat.portRangeSize} as range_start,
            DstAddr as target,
            DstPort,
            count() as attempts,
            CASE
                WHEN DstPort = 22 THEN 'SSH Brute Force'
                WHEN DstPort = 23 THEN 'Telnet Attack'
                WHEN DstPort = 3389 THEN 'RDP Attack'
                WHEN DstPort = 21 THEN 'FTP Attack'
                WHEN DstPort = 3306 THEN 'MySQL Attack'
                WHEN DstPort = 1433 THEN 'MSSQL Attack'
                ELSE 'Unknown'
            END as attack_type
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 1 HOUR
          AND SrcAddr IN (${ipsList})
          AND DstPort IN (21, 22, 23, 3306, 3389, 1433, 5432)
        GROUP BY ip, SrcPort, range_start, target, DstPort
        HAVING attempts > 50
        ORDER BY attempts DESC
        LIMIT 30
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data && data.data.length > 0) {
        const tbody = document.querySelector('#attacks-table tbody');
        tbody.innerHTML = '';

        let criticalCount = 0;

        data.data.forEach(row => {
            const rangeEnd = row.range_start + config.cgnat.portRangeSize - 1;

            if (row.attempts > 100) criticalCount++;

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td><span class="ip-badge">${row.ip}</span></td>
                <td>${row.SrcPort}</td>
                <td><span class="port-range">${row.range_start}-${rangeEnd}</span></td>
                <td><span class="ip-badge">${row.target}</span></td>
                <td>${row.DstPort}</td>
                <td class="danger">${row.attack_type}</td>
                <td class="danger">${formatNumber(row.attempts)}</td>
                <td><button class="nav-btn" onclick="alert('Bloquear range ${row.range_start}-${rangeEnd}')">🚫 Bloquear</button></td>
            `;
            tbody.appendChild(tr);
        });

        document.getElementById('suspicious-count').textContent = data.data.length;

        // Atualizar alertas
        const alertsDiv = document.getElementById('security-alerts');
        if (criticalCount > 0) {
            alertsDiv.innerHTML = `
                <div class="alert">
                    <strong class="danger">⚠️ ${criticalCount} ataque(s) crítico(s) detectado(s)!</strong><br>
                    <small>Verifique a tabela de ataques abaixo para detalhes.</small>
                </div>
            `;
        } else {
            alertsDiv.innerHTML = `
                <div class="alert alert-warning">
                    <strong>⚠️ ${data.data.length} atividade(s) suspeita(s) detectada(s)</strong><br>
                    <small>Monitorar comportamento.</small>
                </div>
            `;
        }
    } else {
        document.querySelector('#attacks-table tbody').innerHTML =
            '<tr><td colspan="8" style="text-align: center; color: #10b981;">✓ Nenhum ataque detectado</td></tr>';

        document.getElementById('suspicious-count').textContent = '0';
        document.getElementById('security-alerts').innerHTML = `
            <div class="alert" style="background: #f0fdf4; border-left-color: #10b981;">
                <strong style="color: #10b981;">✓ Sistema Seguro</strong><br>
                <small>Nenhuma atividade suspeita detectada na última hora.</small>
            </div>
        `;
    }
}

// Top consumidores
async function updateTopConsumers() {
    const ipsList = config.cgnat.ips.map(ip => `'${ip}'`).join(',');

    const query = `
        SELECT
            SrcAddr as ip,
            floor(SrcPort / ${config.cgnat.portRangeSize}) * ${config.cgnat.portRangeSize} as range_start,
            sum(Bytes) as total_bytes,
            count() as total_flows,
            uniq(DstAddr) as active_connections
        FROM akvorado.flows
        WHERE TimeReceived > now() - INTERVAL 1 HOUR
          AND SrcAddr IN (${ipsList})
        GROUP BY ip, range_start
        ORDER BY total_bytes DESC
        LIMIT 20
        FORMAT JSON
    `;

    const data = await executeQuery(query);

    if (data && data.data) {
        const tbody = document.querySelector('#top-consumers-table tbody');
        tbody.innerHTML = '';

        data.data.forEach((row, index) => {
            const rangeEnd = row.range_start + config.cgnat.portRangeSize - 1;

            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${index + 1}</td>
                <td><span class="ip-badge">${row.ip}</span></td>
                <td><span class="port-range">${row.range_start}-${rangeEnd}</span></td>
                <td>${formatBytes(row.total_bytes)}</td>
                <td>${formatNumber(row.total_flows)}</td>
                <td>${row.active_connections}</td>
            `;
            tbody.appendChild(tr);
        });
    }
}

// Atualizar tudo
async function refreshAll() {
    console.log('Atualizando análise CGNAT...');

    await Promise.all([
        updateCGNATSummary(),
        updatePortRangeActivity(),
        detectPortScanning(),
        detectAttacks(),
        updateTopConsumers()
    ]);

    console.log('Atualização concluída!');
}

// Inicializar
document.addEventListener('DOMContentLoaded', async () => {
    console.log('Dashboard CGNAT inicializado');
    loadSettings();
    await refreshAll();
    setInterval(refreshAll, config.refreshInterval);
});
