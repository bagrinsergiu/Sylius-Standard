ARG PHP_VERSION=7.4

FROM php:${PHP_VERSION}-fpm AS sylius_php

RUN apt-get update \
    && apt-get install -y wget unzip nano sudo acl \
    && apt-get install -y nginx \
    && apt-get install -y \
        libzip-dev libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libpng-dev libicu-dev libpq-dev libonig-dev libwebp-dev \
    && docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) zip mbstring json gd iconv pcntl intl pdo pdo_mysql opcache exif \
    && docker-php-source delete && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/*

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer
COPY docker/php/php.ini /usr/local/etc/php/php.ini
COPY docker/php/php-cli.ini /usr/local/etc/php/php-cli.ini

#nginx
COPY docker/nginx/conf.d/default.conf /etc/nginx/conf.d/
RUN rm -rf /etc/nginx/sites-enabled/*

# https://getcomposer.org/doc/03-cli.md#composer-allow-superuser
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN set -eux; \
	composer clear-cache
ENV PATH="${PATH}:/root/.composer/vendor/bin"

WORKDIR /srv/sylius

# build for production
ARG APP_ENV=prod

# prevent the reinstallation of vendors at every changes in the source code
COPY composer.json composer.lock symfony.lock ./
RUN set -eux; \
	composer install --prefer-dist --no-autoloader --no-scripts --no-progress --no-suggest; \
	composer clear-cache

# copy only specifically what we need
COPY .env .env.prod .env.test .env.test_cached ./
COPY bin bin/
COPY config config/
COPY public public/
COPY src src/
COPY templates templates/
COPY translations translations/

RUN set -eux; \
	mkdir -p var/cache var/log; \
	composer dump-autoload --classmap-authoritative; \
	APP_SECRET='' composer run-script post-install-cmd; \
	chmod +x bin/console; sync; \
	bin/console sylius:install:assets; \
	bin/console sylius:theme:assets:install public
VOLUME /srv/sylius/var

VOLUME /srv/sylius/public/media

#copy generated assets
COPY --from=sylius_php /srv/sylius/public public/

COPY docker/php/docker-entrypoint.sh /usr/local/bin/docker-entrypoint
RUN chmod +x /usr/local/bin/docker-entrypoint

ENTRYPOINT ["docker-entrypoint"]
CMD ["php-fpm"]
