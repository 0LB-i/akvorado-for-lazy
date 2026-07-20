# Configuração de GeoIP para Akvorado

O Akvorado usa bancos de dados GeoIP2 da MaxMind para enriquecer os flows com informações geográficas e de ASN.

## Por que usar GeoIP?

Com GeoIP habilitado, você terá:
- País de origem e destino dos flows
- Informações de ASN (Autonomous System Number)
- Cidade e coordenadas geográficas
- Nome da organização/provedor

## Passo a Passo

### 1. Criar Conta MaxMind (Gratuito)

1. Acesse: https://www.maxmind.com/en/geolite2/signup
2. Preencha o formulário de cadastro
3. Confirme seu email
4. Faça login em: https://www.maxmind.com/en/account/login

### 2. Gerar License Key

1. No painel da conta, vá em: **Account → Manage License Keys**
2. Clique em **Generate new license key**
3. Nome: `Akvorado` (ou qualquer nome)
4. Confirme "Will you be using this key for GeoIP Update?" = **No**
5. Copie e salve sua License Key (você só verá uma vez!)

### 3. Baixar Bancos de Dados

#### Opção A: Download Manual (Recomendado)

1. No painel MaxMind, vá em: **Account → Download Databases**
2. Baixe os seguintes arquivos:
   - **GeoLite2 ASN** (formato: GeoIP2 Binary .mmdb)
   - **GeoLite2 Country** (formato: GeoIP2 Binary .mmdb)
   - **GeoLite2 City** (formato: GeoIP2 Binary .mmdb)

#### Opção B: Download via Link Direto (com License Key)

```bash
# Substitua YOUR_LICENSE_KEY pela sua chave
LICENSE_KEY="YOUR_LICENSE_KEY"

cd data/geoip/

# Download GeoLite2-ASN
curl -o GeoLite2-ASN.tar.gz \
  "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-ASN&license_key=${LICENSE_KEY}&suffix=tar.gz"
tar -xzf GeoLite2-ASN.tar.gz --strip-components=1 "*/GeoLite2-ASN.mmdb"
rm GeoLite2-ASN.tar.gz

# Download GeoLite2-Country
curl -o GeoLite2-Country.tar.gz \
  "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=${LICENSE_KEY}&suffix=tar.gz"
tar -xzf GeoLite2-Country.tar.gz --strip-components=1 "*/GeoLite2-Country.mmdb"
rm GeoLite2-Country.tar.gz

# Download GeoLite2-City
curl -o GeoLite2-City.tar.gz \
  "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-City&license_key=${LICENSE_KEY}&suffix=tar.gz"
tar -xzf GeoLite2-City.tar.gz --strip-components=1 "*/GeoLite2-City.mmdb"
rm GeoLite2-City.tar.gz

echo "Download concluído!"
```

### 4. Instalar os Arquivos

Copie os arquivos `.mmdb` para o diretório correto:

```bash
# Se baixou manualmente
cp ~/Downloads/GeoLite2-*.mmdb data/geoip/

# Verificar arquivos
ls -lh data/geoip/
```

Você deve ter:
- `GeoLite2-ASN.mmdb`
- `GeoLite2-Country.mmdb`
- `GeoLite2-City.mmdb`

### 5. Reiniciar Akvorado

```bash
docker-compose restart
```

### 6. Verificar Funcionamento

Após reiniciar, acesse a interface web e verifique se os flows mostram informações de país e ASN.

Ou consulte diretamente no ClickHouse:

```bash
docker exec akvorado-clickhouse clickhouse-client --query="
SELECT
    SrcCountry,
    DstCountry,
    SrcAS,
    DstAS,
    count() as flows
FROM akvorado.flows
WHERE TimeReceived > now() - INTERVAL 1 HOUR
GROUP BY SrcCountry, DstCountry, SrcAS, DstAS
LIMIT 10
"
```

## Atualização Automática (Opcional)

Para atualização automática dos bancos GeoIP, edite `config/akvorado.yaml`:

```yaml
geoip:
  enabled: true

  # Databases
  asn-database: /var/lib/geoip/GeoLite2-ASN.mmdb
  country-database: /var/lib/geoip/GeoLite2-Country.mmdb
  city-database: /var/lib/geoip/GeoLite2-City.mmdb

  # Habilitar atualização automática
  auto-update:
    enabled: true
    account-id: YOUR_ACCOUNT_ID
    license-key: YOUR_LICENSE_KEY
    interval: 168h  # Semanal
```

Depois reinicie:
```bash
docker-compose restart
```

## Troubleshooting

### Arquivos não encontrados

```bash
# Verificar se arquivos existem
ls -lh data/geoip/

# Verificar permissões
chmod 644 data/geoip/*.mmdb
```

### GeoIP não funciona

```bash
# Verificar logs
docker-compose logs akvorado-orchestrator | grep -i geoip

# Verificar configuração
docker exec akvorado-orchestrator cat /etc/akvorado/akvorado.yaml | grep -A 10 geoip
```

### Atualização automática falha

Verifique:
1. Account ID e License Key corretos
2. Conectividade com internet do container
3. Logs: `docker-compose logs akvorado-orchestrator`

## Tamanho dos Arquivos

Os bancos GeoIP2 ocupam aproximadamente:
- GeoLite2-ASN.mmdb: ~7 MB
- GeoLite2-Country.mmdb: ~6 MB
- GeoLite2-City.mmdb: ~70 MB

## Frequência de Atualização

A MaxMind atualiza os bancos GeoLite2:
- **Semanalmente** (terças-feiras)

Configure a atualização automática para manter os dados precisos.

## Alternativas Comerciais

Para maior precisão, considere os bancos pagos da MaxMind:
- GeoIP2 Precision Services
- GeoIP2 Enterprise Database

## Referências

- MaxMind GeoLite2: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data
- Documentação Akvorado: https://demo.akvorado.net/docs/intro
- GeoIP2 Database Format: https://maxmind.github.io/MaxMind-DB/

---

**Nota**: Os bancos GeoLite2 são fornecidos gratuitamente pela MaxMind sob licença Creative Commons.
