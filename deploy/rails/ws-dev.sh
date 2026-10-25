#!/bin/sh
# Verifica Valkey, Sidekiq e Action Cable no desenvolvimento (compose.dev.yml): sobe o servidor e o Sidekiq, assina o canal pela rede do
# compose, dispara `crm:platform_check` e espera os cinco sinais.
set -e
cd "$(dirname "$0")/../.."
C="docker compose -f deploy/rails/compose.dev.yml --env-file deploy/rails/.env.dev"
$C up -d db valkey web sidekiq >/dev/null
$C exec -T web bin/rails db:prepare >/dev/null
sleep 6
docker run --rm --network crm-rails_default -v "$PWD/deploy/rails:/v:ro" -e WS_URL="ws://web:3000/cable" -e WS_ORIGIN=http://web:3000 -e WS_TIMEOUT=60 node:26.12.1-trixie-slim node /v/v5/ws-check.mjs > /tmp/ws-check-rails.log 2>&1 &
PID=$!
for i in $(seq 1 30); do grep -q "SUBSCRIBED\|fechada\|recusada" /tmp/ws-check-rails.log 2>/dev/null && break; sleep 1; done
$C exec -T web bin/rails crm:platform_check >/dev/null
wait $PID && STATUS=0 || STATUS=$?
cat /tmp/ws-check-rails.log
exit $STATUS
