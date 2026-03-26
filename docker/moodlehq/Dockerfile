FROM moodlehq/moodle-php-apache:8.1

ARG MOODLE_RELEASE_STREAM=stable405
ARG MOODLE_PACKAGE=moodle-latest-405.tgz

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl tar \
    && rm -rf /var/lib/apt/lists/*

RUN rm -rf /var/www/html/* \
    && curl -fsSL "https://download.moodle.org/download.php/direct/${MOODLE_RELEASE_STREAM}/${MOODLE_PACKAGE}" -o /tmp/moodle.tgz \
    && tar -xzf /tmp/moodle.tgz -C /tmp \
    && cp -a /tmp/moodle/. /var/www/html/ \
    && rm -rf /tmp/moodle /tmp/moodle.tgz \
    && mkdir -p /var/moodledata \
    && chown -R www-data:www-data /var/www/html /var/moodledata \
    && a2enmod rewrite headers expires

COPY docker/moodlehq/entrypoint.sh /usr/local/bin/esmos-moodle-entrypoint

RUN chmod +x /usr/local/bin/esmos-moodle-entrypoint

ENTRYPOINT ["/usr/local/bin/esmos-moodle-entrypoint"]
CMD ["apache2-foreground"]
