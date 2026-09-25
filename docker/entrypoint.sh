#!/bin/sh
set -e

log() { echo "[voltra] $*"; }

# ---------- Wait for PostgreSQL ----------
if [ -n "$DB_HOST" ]; then
    log "Waiting for DB at $DB_HOST:${DB_PORT:-5432}..."
    until pg_isready -h "$DB_HOST" -p "${DB_PORT:-5432}" -U "${DB_USERNAME:-postgres}" >/dev/null 2>&1; do
        sleep 1
    done
    log "DB ready."
fi

# ---------- Wait for Redis ----------
if [ -n "$REDIS_HOST" ]; then
    log "Waiting for Redis at $REDIS_HOST:${REDIS_PORT:-6379}..."
    until nc -z "$REDIS_HOST" "${REDIS_PORT:-6379}" >/dev/null 2>&1; do
        sleep 1
    done
    log "Redis ready."
fi

# ---------- Ensure writable dirs ----------
mkdir -p \
    storage/logs \
    storage/framework/cache/data \
    storage/framework/sessions \
    storage/framework/views \
    bootstrap/cache \
    /var/log/supervisor

chown -R www-data:www-data storage bootstrap/cache /var/log/supervisor 2>/dev/null || true
chmod -R 775 storage bootstrap/cache /var/log/supervisor 2>/dev/null || true

# ---------- Migrations ----------
if [ "$RUN_MIGRATIONS" = "true" ]; then
    log "Running migrations..."
    php artisan migrate --force
fi

# ---------- Production caches ----------
if [ "$APP_ENV" = "production" ]; then
    log "Caching config/routes/views/events..."
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache

    if [ ! -L public/storage ]; then
        php artisan storage:link || true
    fi
fi

# ---------- Hand off ----------
log "Starting Supervisor: $*"
exec "$@"
