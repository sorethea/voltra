#!/bin/sh
set -e

log() { echo "[voltra] $*"; }

# Wait for MySQL via port check (lightweight, no client needed)
if [ -n "$DB_HOST" ]; then
    log "Waiting for MySQL at $DB_HOST:${DB_PORT:-3306}..."
    until nc -z "$DB_HOST" "${DB_PORT:-3306}" >/dev/null 2>&1; do
        sleep 2
    done
    log "MySQL reachable."
fi

# Wait for Redis
if [ -n "$REDIS_HOST" ]; then
    log "Waiting for Redis at $REDIS_HOST:${REDIS_PORT:-6379}..."
    until nc -z "$REDIS_HOST" "${REDIS_PORT:-6379}" >/dev/null 2>&1; do
        sleep 1
    done
    log "Redis ready."
fi

mkdir -p \
    storage/logs \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache \
    /var/log/supervisor

chown -R www-data:www-data storage bootstrap/cache /var/log/supervisor 2>/dev/null || true
chmod -R 775 storage bootstrap/cache /var/log/supervisor 2>/dev/null || true

if [ "$RUN_MIGRATIONS" = "true" ]; then
    log "Running migrations..."
    php artisan migrate --force
fi

if [ "$APP_ENV" = "production" ]; then
    log "Caching config/routes/views/events..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache
    [ ! -L public/storage ] && php artisan storage:link || true
fi

log "Starting Supervisor: $*"
exec "$@"
