#!/bin/sh
# Verifica o Action Cable pelo caminho do usuário: o navegador-simulado (Node) assina o canal da plataforma e o contêiner da aplicação enfileira um job em
# cada fila do Sidekiq; cada job transmite um sinal, e os cinco precisam chegar.
# Uso: deploy/rails/v5/ws-check.sh [url base] [diretório da instalação]   (padrão: http://127.0.0.1:3220 e ./instalacao)
set -e
cd "$(dirname "$0")"
BASE=${1:-http://127.0.0.1:3220}
INSTALACAO=${2:-./instalacao}
WS=$(echo "$BASE" | sed 's|^https|wss|; s|^http|ws|')/cable
LOG=$(mktemp)
docker run --rm --network host ${V5_ADD_HOST:+--add-host $V5_ADD_HOST} -v "$PWD:/v:ro" -e WS_URL="$WS" -e WS_ORIGIN="$BASE" -e WS_TIMEOUT=90 node:26.12.1-trixie-slim node /v/ws-check.mjs > "$LOG" 2>&1 &
PID=$!
for i in $(seq 1 30); do grep -q "SUBSCRIBED\|fechada\|recusada" "$LOG" 2>/dev/null && break; sleep 1; done
(cd "$INSTALACAO" && docker compose -f compose.yml --env-file .env.producao exec -T app bin/rails crm:platform_check) >/dev/null
wait $PID && STATUS=0 || STATUS=$?
cat "$LOG"; rm -f "$LOG"
exit $STATUS
