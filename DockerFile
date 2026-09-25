# ============================================================
# Voltra · ខែលអគ្គីសនី — Production Dockerfile
# Multi-stage: Composer → Node → PHP-FPM + Nginx + Supervisor
# ============================================================

# ============================================================
# Stage 1 — Composer dependencies
# ============================================================
FROM composer:2.8 AS composer-stage

WORKDIR /app

COPY composer.json composer.lock ./

RUN composer install \
    --no-interaction \
    --no-dev \
    --prefer-dist \
    --no-scripts \
    --no-autoloader \
    --optimize-autoloader

# ============================================================
# Stage 2 — Frontend assets (Vite / Tailwind / Filament)
# ============================================================
FROM node:22-alpine AS node-stage

WORKDIR /app

COPY package.json package-lock.json ./

RUN npm ci

COPY . .

RUN npm run build

# ============================================================
# Stage 3 — Final runtime
# ============================================================
FROM php:8.4-fpm-alpine AS runtime

LABEL org.opencontainers.image.title="Voltra" \
      org.opencontainers.image.description="Voltra · ខែលអគ្គីសនី — EV logbook" \
      org.opencontainers.image.vendor="Voltra" \
      org.opencontainers.image.url="https://voltra.app"

# ---------- System packages ----------
RUN apk add --no-cache \
    nginx \
    supervisor \
    curl \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    oniguruma-dev \
    libxml2-dev \
    libzip-dev \
    icu-dev \
    postgresql-dev \
    postgresql-client \
    zip \
    unzip \
    git \
    tzdata

# ---------- Timezone ----------
ENV TZ=Asia/Phnom_Penh
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ---------- PHP extensions ----------
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_pgsql \
        pgsql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        intl \
        opcache \
        zip

# ---------- Redis extension ----------
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

# ---------- PHP config ----------
COPY docker/php/local.ini /usr/local/etc/php/conf.d/99-voltra.ini

WORKDIR /var/www/html

# ---------- Composer binary ----------
COPY --from=composer-stage /usr/bin/composer /usr/bin/composer

# ---------- Vendor from stage 1 ----------
COPY --from=composer-stage /app/vendor ./vendor

# ---------- App source ----------
COPY . .

# ---------- Built assets from stage 2 ----------
COPY --from=node-stage /app/public/build ./public/build

# ---------- Autoloader ----------
RUN composer dump-autoload --optimize --classmap-authoritative --no-scripts

# ---------- Directories + permissions ----------
RUN mkdir -p \
        storage/logs \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/app/public \
        bootstrap/cache \
        /var/log/supervisor \
        /var/run \
    && chown -R www-data:www-data storage bootstrap/cache /var/log/supervisor \
    && chmod -R 775 storage bootstrap/cache /var/log/supervisor

# ---------- Config files ----------
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY docker/supervisor/supervisor-event-listener.sh /usr/local/bin/supervisor-event-listener.sh
RUN chmod +x /usr/local/bin/supervisor-event-listener.sh

# ---------- Entrypoint ----------
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ---------- Expose ----------
EXPOSE 80

# ---------- Healthcheck ----------
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost/up || exit 1

# ---------- Boot ----------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
