#!/bin/sh
# Script de inicialização do console

cat > /tmp/config.yaml <<EOF
http:
  listen: "0.0.0.0:8000"
clickhouse:
  servers:
    - "clickhouse:9000"
  database: "akvorado"
  username: "akvorado"
  password: "akvorado123"
EOF

exec /usr/local/bin/akvorado console /tmp/config.yaml
