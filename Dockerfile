# ============================================================
# Voltra · ខែលអគ្គីសនី — Dockerfile (MySQL, external DB)
# ============================================================

FROM composer:2.8 AS composer-stage
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install \
    --no-interaction --no-dev --prefer-dist \
    --no-scripts --no-autoloader --optimize-autoloader

FROM node:22-alpine AS node-stage
WORKDIR /app
COPY package.json ./
COPY package-lock.json* ./
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npm run build

FROM php:8.4-fpm-alpine AS runtime

LABEL org.opencontainers.image.title="Voltra" \
      org.opencontainers.image.description="Voltra · ខែលអគ្គីសនី" \
      org.opencontainers.image.vendor="Voltra"

# System packages — note mariadb-client for mysqladmin wait
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
    mariadb-client \
    zip \
    unzip \
    git \
    tzdata

ENV TZ=Asia/Phnom_Penh
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# PHP extensions (MySQL)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        mysqli \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        intl \
        opcache \
        zip

# Redis extension
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

# PHP config
COPY docker/php/local.ini /usr/local/etc/php/conf.d/99-voltra.ini

WORKDIR /var/www/html

COPY --from=composer-stage /usr/bin/composer /usr/bin/composer
COPY --from=composer-stage /app/vendor ./vendor
COPY . .
COPY --from=node-stage /app/public/build ./public/build

RUN composer dump-autoload --optimize --classmap-authoritative --no-scripts

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

COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/supervisor/supervisord.conf /etc/supervisord.conf
COPY docker/supervisor/supervisor-event-listener.sh /usr/local/bin/supervisor-event-listener.sh
RUN chmod +x /usr/local/bin/supervisor-event-listener.sh

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost/up || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
