#!/bin/sh
# Entrada dos contêineres do CRM em Laravel. Papel pelo primeiro argumento: app, worker ou scheduler.
set -e
cd /app

# Caches de configuração, rotas, eventos e visões, gerados com o ambiente deste contêiner.
php artisan optimize --no-interaction >/dev/null

case "$1" in
    app)
        # Uma só instância aplica as migrações (RUN_MIGRATIONS=1), antes de atender.
        if [ "${RUN_MIGRATIONS:-0}" = "1" ]; then php artisan migrate --force --no-interaction; fi
        exec php-fpm
        ;;
    worker)
        exec php -d memory_limit=900M artisan queue:work --tries=1 --timeout=900 --memory=768 --sleep=2 --max-time=3600
        ;;
    scheduler)
        exec php artisan schedule:work
        ;;
    *)
        exec "$@"
        ;;
esac
