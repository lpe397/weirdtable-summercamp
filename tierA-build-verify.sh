#!/usr/bin/env bash
# Tier A: build the immutable image, bring up the stack, and run the OBJECTIVE
# checks (baked plugins present, container serving, no PHP fatals in logs).
# The BuddyPress FUNCTIONAL smoke test (components + xProfile) is done after,
# in the browser, per CLAUDE.md. Run on wp01 from /srv/aegis/wordpress.
set -euo pipefail
cd /srv/aegis/wordpress

echo "==================== BUILD + UP ===================="
sudo docker compose up -d --build

echo "==================== WAIT FOR HEALTHY ===================="
# give the entrypoint time to copy /usr/src/wordpress -> /var/www/html and start apache
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1/wp-admin/install.php || true)
  echo "  attempt $i: install.php -> HTTP $code"
  [ "$code" = "200" ] && break
  sleep 3
done

echo "==================== BAKED PLUGINS ===================="
# expect: akismet, buddypress, hello.php, index.php, wp-mail-smtp
sudo docker compose exec -T wordpress ls -1 wp-content/plugins

echo "==================== WP VERSION (served tree) ===================="
sudo docker compose exec -T wordpress sh -c 'grep "\$wp_version =" wp-includes/version.php'

echo "==================== IMMUTABLE DEFINES (runtime) ===================="
sudo docker compose exec -T wordpress php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA")); var_dump(DISALLOW_FILE_MODS, AUTOMATIC_UPDATER_DISABLED);'

echo "==================== LOG SCAN (fatals?) ===================="
if sudo docker compose logs --tail=80 wordpress | grep -iE 'PHP Fatal|Fatal error|Uncaught'; then
  echo ">>> FATALS FOUND ABOVE <<<"
else
  echo "no PHP fatals in last 80 log lines"
fi

echo "==================== DONE (objective checks) ===================="
