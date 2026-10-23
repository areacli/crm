# Imagem do CRM em Laravel 13 (decisão 0013). Contexto de build: a raiz do repositório.
# No PHP 8.5 o opcache já vem embutido no núcleo: não entra no docker-php-ext-install (a tentativa falhava com "cp: cannot stat modules/*").
# Alvo "app": PHP 8.5 com as extensões do projeto e o Composer. Os pacotes entram por composer install no alvo "dependencias".
FROM php:8.5.12-cli-trixie AS app
ENV COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_NO_INTERACTION=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev libicu-dev libzip-dev libonig-dev unzip git ca-certificates \
 && docker-php-ext-install -j"$(nproc)" pdo_pgsql intl zip bcmath pcntl mbstring sockets \
 && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2.10.3 /usr/bin/composer /usr/bin/composer
WORKDIR /app

# Alvo "testes": a imagem da aplicação mais Node e o Chromium do Playwright, para o Pest com navegador (V2) e as
# capturas de tela. Os navegadores ficam na imagem; o pacote playwright vai no package.json da aplicação.
FROM app AS testes
COPY --from=node:26.12.1-trixie-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:26.12.1-trixie-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/navegadores
RUN npm install -g playwright@1.64.1 \
 && playwright install --with-deps chromium \
 && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------------------------------------
# Produção (decisão 0013): PHP-FPM e nginx em imagens separadas, sem pacotes de desenvolvimento nem Node.
# Contexto de build: a raiz do repositório. Alvos: producao-app (PHP-FPM, worker e agendador) e producao-web (nginx).
# ---------------------------------------------------------------------------------------------------------

# Dependências PHP sem as de desenvolvimento.
FROM app AS dependencias
COPY src/composer.json src/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction

# CSS (Tailwind) e demais arquivos do Vite.
FROM node:26.12.1-trixie-slim@sha256:36793bcbb160a6a16cede1e62b93f84e26b78a972a8a4c0b879c1c12f22761ec AS assets
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
WORKDIR /app
COPY src/package.json src/package-lock.json ./
RUN npm ci
COPY --from=dependencias /app/vendor ./vendor
COPY src/ ./
RUN npm run build

FROM php:8.5.12-fpm-trixie@sha256:f665ad19c093eee54db3a03c89102d6828b1bbf4f327689e5947a8686c6585a1 AS producao-app
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq5 libicu76 libzip5 \
 && apt-get install -y --no-install-recommends libpq-dev libicu-dev libzip-dev libonig-dev \
 && docker-php-ext-install -j"$(nproc)" pdo_pgsql intl zip bcmath pcntl mbstring \
 && apt-get purge -y libpq-dev libicu-dev libzip-dev libonig-dev \
 && rm -rf /var/lib/apt/lists/*
COPY --from=composer:2.10.3 /usr/bin/composer /usr/bin/composer
COPY deploy/laravel/php/crm.ini /usr/local/etc/php/conf.d/crm.ini
WORKDIR /app
COPY --from=dependencias /app/vendor ./vendor
COPY src/ ./
COPY --from=assets /app/public/build ./public/build
# Os diretórios de trabalho do Laravel não vêm do código (o .dockerignore os exclui) e precisam existir antes de qualquer
# comando do artisan; a chave abaixo existe só durante a montagem.
RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs storage/app/private bootstrap/cache \
 && APP_KEY=base64:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= composer dump-autoload --optimize --classmap-authoritative --no-dev --no-interaction \
 && rm -f /usr/bin/composer \
 && chown -R www-data:www-data storage bootstrap/cache
COPY deploy/laravel/entrypoint.sh /usr/local/bin/crm-entrypoint
USER www-data
ENTRYPOINT ["crm-entrypoint"]
CMD ["app"]

FROM nginx:1.31.8-trixie@sha256:6e67f8eaac94fc456588d4ff6c470d984841f5b5dc4279863d5cbe6ec5a60def AS producao-web
COPY --from=producao-app /app/public /app/public
COPY deploy/laravel/nginx/default.conf /etc/nginx/conf.d/default.conf
