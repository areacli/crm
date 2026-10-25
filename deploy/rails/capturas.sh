#!/bin/sh
# Recria as fotos do README (docs/telas) com o estado atual da aplicação, pelo teste de sistema `capturas_test.rb`.
# Uso: deploy/rails/capturas.sh   (grava em docs/telas; commite as imagens e atualize o README)
set -e
cd "$(dirname "$0")"
rm -rf ../../src/tmp/capturas
docker compose -f compose.dev.yml --env-file .env.dev run --rm -e CAPTURAS=1 testes bin/rails test test/system/capturas_test.rb
mkdir -p ../../docs/telas
cp ../../src/tmp/capturas/*.png ../../docs/telas/
echo "Fotos em docs/telas: $(ls ../../docs/telas | wc -l) arquivos."
