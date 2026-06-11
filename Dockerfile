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

# Pretty permalinks (required by BuddyPress 12+ rewrites for directory + member
# pages). The base Debian Apache sets AllowOverride None on /var/www, so the
# WordPress .htaccess rewrite rules are ignored and every pretty URL 404s.
# Permit overrides on the docroot, ensure mod_rewrite, and bake the standard
# WordPress .htaccess — the entrypoint copies it from the source tree into the
# docroot on container start. Static + immutable (DISALLOW_FILE_MODS won't let
# WP regenerate it at runtime, which is exactly what we want).
RUN set -eux; \
    a2enmod rewrite; \
    printf '%s\n' '<Directory /var/www/html/>' '    AllowOverride All' '</Directory>' \
      > /etc/apache2/conf-available/wp-permalinks.conf; \
    a2enconf wp-permalinks; \
    { \
      echo '# BEGIN WordPress'; \
      echo '<IfModule mod_rewrite.c>'; \
      echo 'RewriteEngine On'; \
      echo 'RewriteBase /'; \
      echo 'RewriteRule ^index\.php$ - [L]'; \
      echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
      echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
      echo 'RewriteRule . /index.php [L]'; \
      echo '</IfModule>'; \
    } > /usr/src/wordpress/.htaccess; \
    chown www-data:www-data /usr/src/wordpress/.htaccess
