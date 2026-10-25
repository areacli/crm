#!/bin/sh
# Verifica pelo caminho do usuário que o sino do cabeçalho recebe o aviso sem recarregar (Action Cable, decisão 0020). O navegador espera com a página
# aberta; este script cria o aviso para o operador público no contêiner da aplicação.
# Uso: deploy/rails/v5/sino-check.sh [url base] [diretório da instalação]   (padrão: http://127.0.0.1:3220 e ./instalacao)
set -e
cd "$(dirname "$0")"
BASE=${1:-http://127.0.0.1:3220}
INSTALACAO=${2:-./instalacao}
DOMAIN=${CRM_DEMO_DOMAIN:-demo.crm.areacli.com}
LOG=$(mktemp)
./v5.sh sino-check.mjs "$BASE" operador > "$LOG" 2>&1 &
PID=$!
for i in $(seq 1 120); do grep -q PRONTO "$LOG" 2>/dev/null && break; sleep 1; done
(cd "$INSTALACAO" && docker compose -f compose.yml --env-file .env.producao exec -T app bin/rails runner \
    "Notice.create!(user: User.find_by!(email_address: 'operador@${DOMAIN}'), kind: 'linked_to_tenant', data: { tenant_name: 'Escola Alfa', actor_name: 'Verificação', profile_name: 'Operador' })") >/dev/null 2>&1 || true
wait $PID && STATUS=0 || STATUS=$?
cat "$LOG"; rm -f "$LOG"
exit $STATUS
