# Summercamp WordPress — immutable image
# Parent theme (Twenty Twenty-Five) ships in the base image.
# TIER A: keystone community plugin + mail transport only. Child theme,
# hardening MU-plugin, registration gate, and event-workflow plugins
# come in later rebuilds (each verified on its own).
FROM wordpress:6.9-apache

# Minimal Debian image lacks unzip; need it + curl/ca-certs to fetch pinned zips
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl unzip; \
    rm -rf /var/lib/apt/lists/*

# Bake into the SOURCE tree; entrypoint copies it to /var/www/html on start
WORKDIR /usr/src/wordpress
RUN set -eux; \
    for p in \
        "buddypress.14.3.4" \
        "wp-mail-smtp.4.8.0" \
    ; do \
        curl -fsSL -o /tmp/p.zip "https://downloads.wordpress.org/plugin/${p}.zip"; \
        unzip -q /tmp/p.zip -d wp-content/plugins/; \
        rm /tmp/p.zip; \
    done
