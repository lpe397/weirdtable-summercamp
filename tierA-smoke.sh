#!/usr/bin/env bash
# Tier A BuddyPress functional smoke test (the accepted gate), scripted via wp-cli.
# wp-cli is dropped into the RUNNING container only — the image stays immutable
# and it disappears on the next rebuild. Run on wp01 from /srv/aegis/wordpress.
#
# Gate (CLAUDE.md §3 Tier A): install WP -> activate BuddyPress + WP Mail SMTP ->
# enable Activity + Extended Profiles -> Activity directory renders -> create the
# "Mailing Address" xProfile field -> member profile renders -> NO PHP fatals.
set -uo pipefail
cd /srv/aegis/wordpress

IP=172.22.3.26
DC="sudo docker compose"
# wp-cli as www-data; HOME/cache to /tmp (www-data home isn't writable)
WP="$DC exec -T -u www-data -e HOME=/tmp -e WP_CLI_CACHE_DIR=/tmp wordpress wp"

echo "==================== 0. wp-cli into running container ===================="
$DC exec -T wordpress sh -c 'command -v wp >/dev/null 2>&1 || { \
  curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
  && chmod +x /usr/local/bin/wp; }' || { echo "FATAL: wp-cli install failed"; exit 1; }
$WP --info | sed -n '1,4p'

echo "==================== 1. install WordPress ===================="
if $WP core is-installed 2>/dev/null; then
  echo "WP already installed; skipping core install"
else
  ADMIN_PASS=$(openssl rand -base64 18)
  $WP core install --url="http://$IP" --title="Summercamp" \
    --admin_user=scadmin --admin_password="$ADMIN_PASS" \
    --admin_email="guru@aegistech.systems" --skip-email \
    || { echo "FATAL: core install failed"; exit 1; }
  echo ">>> RECORD THESE ADMIN CREDS -> user: scadmin  pass: $ADMIN_PASS"
fi
# BuddyPress 12+ rewrites require pretty permalinks
$WP rewrite structure '/%postname%/' --hard >/dev/null
$WP rewrite flush --hard >/dev/null
echo "permalinks: $($WP option get permalink_structure)"

echo "==================== 2. activate plugins ===================="
$WP plugin activate buddypress wp-mail-smtp
echo "-- active plugins --"
$WP plugin list --status=active --field=name

echo "==================== 3. enable components (Activity + xProfile) ===================="
$WP bp component activate activity  2>&1 | tail -1
$WP bp component activate xprofile  2>&1 | tail -1
echo "-- active components --"
$WP bp component list --status=active --fields=id,title 2>&1 || $WP bp component list 2>&1
# force directory-page creation for whatever is active (don't assume activation did)
$WP eval 'if(function_exists("bp_core_add_page_mappings")){bp_core_add_page_mappings(bp_get_option("bp-active-components"),"keep");echo "page mappings ensured\n";}' 2>&1

echo "==================== 4. render Activity directory ===================="
ACT_URL=$($WP eval 'echo function_exists("bp_get_activity_directory_url")?bp_get_activity_directory_url():(function_exists("bp_get_activity_directory_permalink")?bp_get_activity_directory_permalink():"");' 2>/dev/null)
echo "activity dir url: ${ACT_URL:-<none>}"
ACT_CODE=000
if [ -n "${ACT_URL:-}" ]; then
  ACT_CODE=$(curl -s -o /tmp/act.html -w '%{http_code}' "$ACT_URL")
  echo "activity GET -> HTTP $ACT_CODE   (buddypress markers: $(grep -ic 'buddypress\|activity-list\|id=\"activity' /tmp/act.html))"
fi

echo "==================== 5. xProfile field 'Mailing Address' ===================="
$WP bp xprofile field create --type=textbox --field-group-id=1 --name="Mailing Address" 2>&1 | tail -2
echo "-- fields in base group --"
$WP bp xprofile field list --field-group-id=1 --fields=id,name,type 2>&1
XPROF_OK=$($WP bp xprofile field list --field-group-id=1 --field=name 2>/dev/null | grep -c 'Mailing Address')

echo "==================== 6. render a member profile ===================="
PROF_URL=$($WP eval 'echo function_exists("bp_members_get_user_url")?bp_members_get_user_url(1):(function_exists("bp_core_get_user_domain")?bp_core_get_user_domain(1):"");' 2>/dev/null)
echo "admin profile url: ${PROF_URL:-<none>}"
PROF_CODE=000
[ -n "${PROF_URL:-}" ] && PROF_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$PROF_URL")
echo "profile GET -> HTTP $PROF_CODE"

echo "==================== 7. PHP fatal scan ===================="
if $DC logs --tail=150 wordpress | grep -iE 'PHP Fatal|Fatal error|Uncaught'; then
  FATALS=1; echo ">>> FATALS FOUND ABOVE <<<"
else
  FATALS=0; echo "no PHP fatals in last 150 log lines"
fi

echo "==================== GATE SUMMARY ===================="
BP_ON=$($WP plugin list --status=active --field=name | grep -c '^buddypress$')
SMTP_ON=$($WP plugin list --status=active --field=name | grep -c '^wp-mail-smtp$')
pass(){ [ "$1" = "1" ] && echo "PASS" || echo "FAIL"; }
echo "  BuddyPress active ........ $(pass $BP_ON)"
echo "  WP Mail SMTP active ...... $(pass $SMTP_ON)"
echo "  Activity dir renders ..... $([ "$ACT_CODE" = "200" ] && echo PASS || echo "FAIL ($ACT_CODE)")"
echo "  xProfile field created ... $([ "${XPROF_OK:-0}" -ge 1 ] && echo PASS || echo FAIL)"
echo "  Member profile renders ... $([ "$PROF_CODE" = "200" ] && echo PASS || echo "FAIL ($PROF_CODE)")"
echo "  No PHP fatals ............ $([ "$FATALS" = "0" ] && echo PASS || echo FAIL)"
