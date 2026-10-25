#!/bin/sh
# Roda um script da V5 (navegador Playwright em contêiner, imagem fixada; nada é instalado no sistema) contra uma URL base.
# Uso: deploy/rails/v5/v5.sh <script.mjs> [url base] [gestor|operador]
#      deploy/rails/v5/v5.sh v5-demo.mjs http://127.0.0.1:3220
#      deploy/rails/v5/v5.sh rolagem.mjs https://crm.areacli.com operador        (LARGURA=390 para a tela estreita)
# O usuário é o gestor público da demonstração; com "operador" no terceiro argumento, o operador público.
# Em http://127.0.0.1:<porta> a aplicação assume TLS (como atrás do nginx): um terminador TLS autoassinado (tls-proxy.mjs) sobe dentro do contêiner e o
# navegador usa https://127.0.0.1:3443 (CRM_ORIGINS precisa listar essa origem para o WebSocket).
set -e
cd "$(dirname "$0")"
SCRIPT=${1:?informe o script (.mjs)}
BASE=${2:-http://127.0.0.1:3220}
WHO=${3:-gestor}
DOMAIN=${CRM_DEMO_DOMAIN:-demo.crm.areacli.com}
TELAS=${V5_TELAS_HOST:-/tmp/v5-telas}
mkdir -p "$TELAS"
docker image inspect crm-rails-v5:1.55.0 >/dev/null 2>&1 || docker build -q -t crm-rails-v5:1.55.0 . >/dev/null
PROXY=""
case "$BASE" in
  http://127.0.0.1:*|http://localhost:*)
    PORTA=${BASE##*:}
    PROXY="openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/proxy-key.pem -out /tmp/proxy-cert.pem -subj /CN=127.0.0.1 -days 1 -addext subjectAltName=IP:127.0.0.1 >/dev/null 2>&1; TARGET_PORT=$PORTA node tls-proxy.mjs >/dev/null & sleep 1;"
    BASE="https://127.0.0.1:3443" ;;
esac
# V5_ADD_HOST=nome:ip fixa o endereço no contêiner (quando o resolvedor do servidor falha em nome público).
exec docker run --rm --network host ${V5_ADD_HOST:+--add-host $V5_ADD_HOST} -v "$PWD:/src:ro" -v "$TELAS:/telas" \
    -e BASE_URL="$BASE" -e V5_EMAIL="${WHO}@${DOMAIN}" -e V5_SENHA="demonstracao-${WHO}" -e V5_TELAS=/telas -e LARGURA="${LARGURA:-1440}" \
    -e V5_CHECKOUT="${V5_CHECKOUT:-demonstracao-pagamento}" \
    crm-rails-v5:1.55.0 sh -c "cp /src/*.mjs /w/ && cd /w && $PROXY node $SCRIPT"
