# Configuração de GeoIP para Akvorado

O Akvorado usa bancos de dados GeoIP2 da MaxMind para enriquecer os flows com informações geográficas e de ASN.

## Por que usar GeoIP?

Com GeoIP habilitado, você terá:
- País de origem e destino dos flows
- Informações de ASN (Autonomous System Number)
- Cidade e coordenadas geográficas
- Nome da organização/provedor

## Download automático (o que o install.sh faz)

**Não commite os arquivos `.mmdb`/`.tar.gz` da MaxMind neste repositório.**
A licença gratuita do GeoLite2 não permite redistribuir os bancos a
terceiros, e este repositório é público - publicar os arquivos aqui
equivaleria a redistribuição pública, o que pode gerar takedown do GitHub.

Em vez disso, o `scripts/install.sh` baixa os bancos diretamente da
MaxMind usando sua própria license key gratuita (passo a passo abaixo
para gerar a sua). Durante a instalação ele pergunta se você quer
configurar GeoIP agora e, se sim, pede a license key uma única vez -
ela fica salva em `MAXMIND_LICENSE_KEY` no seu `.env` (que é local,
gitignored) e não é pedida de novo em instalações futuras.

Para atualizar os bancos depois (a MaxMind atualiza semanalmente), rode
de novo:

```bash
rm data/geoip/*.mmdb
./scripts/install.sh
./scripts/manage.sh restart
```

## Passo a Passo (gerar sua license key)

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

Com a license key em mãos, rode `./scripts/install.sh` (ou responda "s"
quando ele perguntar sobre GeoIP numa instalação já existente) e cole a
key quando for pedida. As opções manuais abaixo só são necessárias se
você preferir baixar/copiar os arquivos você mesmo.

### 3. Baixar Bancos de Dados

#### Opção A: Download Manual

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

## Configuração no Orchestrator

A configuração real fica em `config/akvorado-orchestrator.yaml` (gerado
automaticamente pelo `scripts/install.sh` a partir do template
`config/akvorado-orchestrator.yaml.example`, já pré-configurado):

```yaml
geoip:
  asn-database:
    - /var/lib/geoip/GeoLite2-ASN.mmdb
  geo-database:
    - /var/lib/geoip/GeoLite2-Country.mmdb
    - /var/lib/geoip/GeoLite2-City.mmdb
  optional: true
```

`asn-database` e `geo-database` aceitam uma lista de caminhos; quando mais
de um é informado, os dados do último da lista têm prioridade sobre os
anteriores (por isso o City vem depois do Country). `optional: true` evita
que o orchestrator falhe ao subir caso os `.mmdb` ainda não existam.
Não existe uma opção de atualização automática nativa nesta versão do
Akvorado - os arquivos `.mmdb` são recarregados automaticamente pelo
orchestrator quando o conteúdo é atualizado em disco.

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
