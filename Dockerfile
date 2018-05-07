#
# This image uses 2 interstage and an php:7.1-apache final stage
# There is a php-fpm-alpine image too
#
# Interstages are:
#   - composer
#   - npm & yarn & grunt
#
# Final stage gets all that generated stuff and add it to the final image
#


############################
#=== composer interstage ===
############################
FROM composer:1.6.1 as composer
WORKDIR /app
COPY scripts/moveVendors.sh ./scripts/
COPY composer.json composer.lock ./
RUN set -x \
 && composer install --verbose --no-dev


########################
#=== yarn interstage ===
########################
FROM node:latest as yarn
WORKDIR /app
COPY phpmyfaq ./phpmyfaq
COPY --from=composer /app/phpmyfaq ./phpmyfaq
COPY package.json yarn.lock Gruntfile.js ./
RUN set -x \
 && npm install node-sass -g --unsafe-perm \
 && yarn install \
 && yarn build


#################################
#=== Final stage with payload ===
#################################
FROM php:7.1-apache as apache

#=== Install gd php dependencie ===
RUN set -x \
 && buildDeps="libpng-dev libjpeg-dev libfreetype6-dev" \
 && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
 \
 && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
 && docker-php-ext-install gd \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== Install ldap php dependencie ===
RUN set -x \
 && buildDeps="libldap2-dev" \
 && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
 \
 && docker-php-ext-configure ldap --with-libdir=lib/x86_64-linux-gnu/ \
 && docker-php-ext-install ldap \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== Install intl, soap opcache, and zip php dependencie ===
RUN set -x \
 && buildDeps="libicu-dev zlib1g-dev libxml2-dev"
 && apt-get update && apt-get install -y ${buildDeps} --no-install-recommends \
 \
 && docker-php-ext-configure intl \
 && docker-php-ext-install intl \
 && docker-php-ext-install zip \
 && docker-php-ext-install soap \
 && docker-php-ext-install opcache \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== Install mysqli php dependencie ===
RUN set -x \
 && docker-php-ext-install mysqli

#=== Install pgsql dependencie ===
RUN set -ex \
 && buildDeps="libpq-dev" \
 && apt-get update && apt-get install -y $buildDeps \
 \
 && docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql \
 && docker-php-ext-install pdo pdo_pgsql pgsql \
 \
 && apt-get purge -y ${buildDeps} \
 && rm -rf /var/lib/apt/lists/*

#=== php default ===
ENV PMF_SITE_NAME=phpMyFAQ \
    PMF_SITE_LANG=en \
    PMF_ENABLE_UPLOADS=On \
    PMF_TIMEZONE="Europe/Berlin" \
    PMF_MEMORY_LIMIT=64M \
    PMF_DISABLE_HTACCESS="" \
    PHP_LOG_ERRORS=On \
    PHP_ERROR_REPORTING=E_ALL

#=== Add source code from previously built interstage ===
COPY --from=yarn /app/phpmyfaq .

#=== Set custom entrypoint ===
COPY docker-entrypoint.sh /entrypoint
RUN chmod +x /entrypoint
ENTRYPOINT [ "/entrypoint" ]

#=== Re-Set CMD as we changed the default entrypoint ===
CMD [ "apache2-foreground" ]


#############################################
#=== Optional alpine stage (with payload) ===
#############################################
FROM php:7.1-fpm-alpine as fpm-alpine

#=== Install gd php dependencie ===
RUN set -x \
 && apk add --no-cache \
  freetype \
  libpng \
  libjpeg-turbo \
 && apk add --no-cache --virtual .build-deps \
  $PHPIZE_DEPS \
  freetype-dev \
  libpng-dev \
  libjpeg-turbo-dev \
 \
 && docker-php-ext-configure gd \
  --with-gd \
  --with-freetype-dir=/usr/include/ \
  --with-png-dir=/usr/include/ \
  --with-jpeg-dir=/usr/include/ \
 && NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
 && docker-php-ext-install -j${NPROC} gd \
 \
 && apk del .build-deps \
 && rm -rf /tmp/* /usr/local/lib/php/doc/* /var/cache/apk/*

#=== Install ldap php dependencie ===
RUN set -x \
 && apk add --no-cache --virtual .build-deps \
  $PHPIZE_DEPS \
  openldap-dev \
 \
 && docker-php-ext-install ldap \
 \
 && apk del .build-deps \
 && rm -rf /tmp/* /usr/local/lib/php/doc/* /var/cache/apk/*

#=== Install intl, soap opcache, and zip php dependencie ===
RUN set -x \
 && apk add --no-cache \
  icu \
 && apk add --no-cache --virtual .build-deps \
  $PHPIZE_DEPS \
  zlib-dev \
  icu-dev \
  libxml2-dev \
 && docker-php-ext-configure intl \
 && docker-php-ext-install intl \
 && docker-php-ext-install zip \
 && docker-php-ext-install soap \
 && docker-php-ext-install opcache \
 \
 && apk del .build-deps \
 && rm -rf /tmp/* /usr/local/lib/php/doc/* /var/cache/apk/*

#=== Install mysqli php dependencie ===
RUN set -x \
 && docker-php-ext-install mysqli

#=== Install pgsql dependencie ===
RUN set -x \
 && apk add --no-cache \
  postgresql-libs \
 && apk add --no-cache --virtual .build-deps \
  $PHPIZE_DEPS \
  postgresql-dev \
 && docker-php-ext-install pgsql \
 \
 && apk del .build-deps \
 && rm -rf /tmp/* /usr/local/lib/php/doc/* /var/cache/apk/*

#=== php default ===
ENV PMF_SITE_NAME=phpMyFAQ \
    PMF_SITE_LANG=en \
    PMF_ENABLE_UPLOADS=On \
    PMF_TIMEZONE="Europe/Berlin" \
    PMF_MEMORY_LIMIT=64M \
    PMF_DISABLE_HTACCESS="" \
    PHP_LOG_ERRORS=On \
    PHP_ERROR_REPORTING=E_ALL

#=== Add source code from previously built interstage ===
COPY --from=yarn /app/phpmyfaq .

#=== Set custom entrypoint ===
COPY docker-entrypoint.sh /entrypoint
RUN chmod +x /entrypoint
ENTRYPOINT [ "/entrypoint" ]

#=== Re-Set CMD as we changed the default entrypoint ===
CMD [ "php-fpm" ]
