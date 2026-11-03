#!/bin/sh
# Instala o OpenUI5 em src/public/ui5 para o ambiente de desenvolvimento e de testes (decisão 0025), num contêiner descartável com curl e unzip.
set -e
cd "$(dirname "$0")/../.."
docker run --rm -v "$PWD/src:/app" -w /app docker.io/library/ruby:4.0.6-trixie sh -c \
  'apt-get update -qq && apt-get install -y -qq --no-install-recommends unzip >/dev/null && bin/ui5-instalar'
