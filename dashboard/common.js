// Utilitários compartilhados entre as páginas do dashboard (dashboard.js,
// asn-analysis.js, attack-analysis.js, cgnat-analysis.js, network-health.js).
// Cada página ainda declara sua própria `config` global antes de carregar
// este arquivo; as funções aqui só a leem/gravam em tempo de chamada.

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

// Lê host/usuário/senha do ClickHouse salvos no localStorage e aplica em
// `config.clickhouse`. Retorna os valores lidos para quem precisar refletir
// isso em campos do próprio formulário da página (só dashboard.js faz isso).
function loadClickHouseSettings() {
    const savedHost = localStorage.getItem('clickhouse-host');
    const savedUser = localStorage.getItem('clickhouse-user');
    const savedPass = localStorage.getItem('clickhouse-pass');

    if (savedHost) config.clickhouse.host = savedHost;
    if (savedUser) config.clickhouse.user = savedUser;
    if (savedPass) config.clickhouse.password = savedPass;

    return { savedHost, savedUser, savedPass };
}

function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatNumber(num) {
    if (num >= 1000000) return (num / 1000000).toFixed(2) + 'M';
    if (num >= 1000) return (num / 1000).toFixed(2) + 'K';
    return num.toString();
}

// União dos países vistos em cada página (o conjunto tinha divergido com o
// tempo: cada arquivo acumulou entradas diferentes por cópia manual).
function getCountryFlag(country) {
    const flags = {
        'BR': '🇧🇷', 'US': '🇺🇸', 'CN': '🇨🇳', 'RU': '🇷🇺',
        'DE': '🇩🇪', 'GB': '🇬🇧', 'FR': '🇫🇷', 'JP': '🇯🇵',
        'AR': '🇦🇷', 'CL': '🇨🇱', 'MX': '🇲🇽', 'ES': '🇪🇸',
        'IT': '🇮🇹', 'CA': '🇨🇦', 'AU': '🇦🇺', 'IN': '🇮🇳',
        'KR': '🇰🇷', 'NL': '🇳🇱'
    };
    return flags[country] || '🌐';
}

// União dos ASNs vistos em cada página. Base = versão mais completa
// (dashboard.js) + entradas exclusivas encontradas em asn-analysis.js.
// Dois conflitos reais foram encontrados e resolvidos, verificando o titular
// via RIPEstat:
// - AS54113: "Fastly" (dashboard.js) vs "FASTNET" (asn-analysis.js) ->
//   titular real é Fastly, Inc.
// - AS28573: asn-analysis.js tinha a chave '28573' duplicada dentro do
//   próprio arquivo ('Claro/NET' sobrescrita por 'Claro S.A' — a 2ª entrada
//   vencia em runtime nesse arquivo). RIPEstat aponta "Claro NXT
//   Telecomunicacoes" como titular; mantido "Claro/NET" por ser o rótulo em
//   que os outros 3 arquivos (dashboard.js, attack-analysis.js,
//   network-health.js) já convergiam.
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
        '16625': 'Akamai CDN',
        '22822': 'Limelight',

        // Provedores Brasileiros - Grandes Operadoras
        '28573': 'Claro/NET',
        '26599': 'TELEFÔNICA BRASIL',
        '7738': 'Telemar/Oi',
        '18881': 'TELEFÔNICA',
        '27699': 'TELEFÔNICA BRASIL',
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
        '262287': 'MaxxLink',
        '264566': 'Digibrás',
        '269141': 'AKINET',
        '28338': 'CLARO NXT',
        '53240': 'COPREL',
        '264979': 'Veloo Telecom',

        // Datacenters e Hosting
        '14061': 'DigitalOcean',
        '397213': 'Cloudflare',
        '209242': 'Cloudflare',
        '63949': 'Linode',
        '19527': 'Google Cloud',
        '394425': 'Contabo',
        '8100': 'QuadraNet',
        '24940': 'Hetzner',
        '16276': 'OVH',
        '12876': 'Scaleway',

        // CDN e Edge
        '14618': 'Amazon CloudFront',
        '393406': 'Bunny CDN',
        '60068': 'CDN77',
        '209103': 'BelugaCDN',

        // Provedores Internacionais Populares
        '174': 'Cogent',
        '3356': 'Level3/Lumen',
        '1299': 'Telia',
        '3257': 'GTT',
        '6939': 'Hurricane Electric',
        '6762': 'Telecom Italia',
        '12956': 'Telefonica',
        '3320': 'Deutsche Telekom',
        '5511': 'Orange France'
    };

    return asnNames[asn.toString()] || `AS${asn}`;
}
