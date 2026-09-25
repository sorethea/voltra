# ============================================================
# Voltra · ខែលអគ្គីសនី — Dockerfile
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
    nodejs \
    npm \
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

# ---------- Timezone ----------
ENV TZ=Asia/Phnom_Penh
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ---------- PHP extensions ----------
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

# ---------- Redis extension ----------
RUN apk add --no-cache --virtual .build-deps $PHPIZE_DEPS \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del .build-deps

# ---------- Composer ----------
COPY --from=composer:2.8 /usr/bin/composer /usr/bin/composer

# ---------- PHP config ----------
COPY docker/php/local.ini /usr/local/etc/php/conf.d/99-voltra.ini

WORKDIR /var/www/html

# ---------- App source ----------
COPY . .

# ---------- Composer install (now extensions exist) ----------
RUN composer install \
        --no-interaction \
        --no-dev \
        --prefer-dist \
        --no-scripts \
        --optimize-autoloader \
    && composer dump-autoload --optimize --classmap-authoritative --no-scripts

# ---------- Regenerate package cache inside the image ----------
RUN rm -f bootstrap/cache/*.php \
    && php artisan package:discover --ansi || true

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

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS http://localhost/up || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
