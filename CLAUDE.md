# WORDPRESS ON wp01 — BUILD SEED / CLAUDE.md (v3)

**Status:** **TIER A DONE.** Image built + deployed to wp01 + BuddyPress
smoke-test gate PASSED on 6.9.4 (BuddyPress 14.3.4 + WP Mail SMTP 4.8.0 activate,
Activity + Extended Profiles enable with no 500, "Mailing Address" xProfile field
creates, ZERO PHP fatals). Pretty-permalink Apache fix baked (AllowOverride +
.htaccess). **One known-open item carried to the configure step:** BP-12 directory
URL rendering (`/activity/`, `/members/`) soft-200s to the homepage — a BuddyPress
*Rewrites* config matter, NOT a 6.9.4 fatal (see §3 Tier A note + §4 lesson 6).
**Next = TIER B** (child theme, registration gate, hardening MU-plugin, Akismet).
NOT done beyond that: HAProxy/TLS/DNS, git-based deploy loop to wp01.
**Date:** 2026-06-11
**Parent project:** Summercamp (self-hosted site to replace the Facebook group)
**Supersedes:** the parked v1 seed (full functional spec / Domino narrative lives
there — read it for the "why").

---

## 0. HOW TO USE / CURRENT TASK FOR CLAUDE CODE

This file is the project memory. Interaction Preferences from the Aegis seed apply
(direct, objective, sudo on admin cmds, delta edits, verify versions before
asserting, one step at a time, challenge bad ideas, no epicycles).

**TIER A COMPLETE** (built, deployed, gate PASSED — see §3 Tier A). **CURRENT TASK
= TIER B.** Rebuild adding: TT25 child theme (style BuddyPress surfaces),
invite-only registration gate, hardening MU-plugin, Akismet activation. **Do NOT
bake the full plugin set in one shot** — keep the tiering so failures stay
localized; verify each addition on its own. Tier C (event workflow) comes after.

**Edit in this repo only.** Deploy to wp01 via the repo→wp01 path (scp for now;
git-pull loop later). Never edit files live on wp01.

---

## 1. DECISIONS LOCKED (do NOT relitigate)

- **WordPress 6.9 branch, NOT 7.0.** 7.0 shipped 2026-05-20 (~3 wks old). 6.9.4 is
  the mature branch; stability-first + BuddyPress block-compat is weakest on a new
  major. 6.9→7.x is a deliberate, snapshot-protected rebuild on our schedule.
- **Theme: Twenty Twenty-Five + a child theme.** TT25 is bundled in core → can
  NEVER block a security patch (dispositive). Accept CSS work on BuddyPress
  surfaces. BuddyX rejected (third-party = can lag core = can block a patch).
- **Repo: this one (`weirdtable-summercamp`, private, `lpe397`)**, NOT the Aegis
  monorepo. Offboarding-first; treat weirdtable as a client.
- **MariaDB = its own container (`mariadb:11.4`), NOT db01.**
- **No Traefik.** Single app; HAProxy on OPNsense terminates TLS → wp01:80.
- **BuddyPress accepted on a SMOKE-TEST gate, not its wordpress.org label.**
  Latest BuddyPress is 14.3.4 and its "tested up to" label sits at ~6.7–6.8
  (below our 6.9 rule), with no scheduled release. No evidence of actual breakage
  on 6.9.x — just a lagging label + slow cadence. There is no viable free
  alternative (BuddyBoss $299/yr, bbPress stalled), and the functional spec needs
  it. So: the gate FOR BUDDYPRESS is "activate it in the built image and exercise
  feed + xProfile on 6.9.4 with no fatals," not the label. For all OTHER plugins,
  the label gate (tested-up-to ≥ 6.9) stays as the first filter.
- **Plugin baking is phased (A/B/C) to localize failures** — see §3.

---

## 2. VALIDATED STATE (built + verified)

### Docker
- Docker CE from Docker's official apt repo, DEB822 `.sources`, suite `trixie`,
  component `stable`. Docker CE 29.x, compose plugin v5.1.4. hello-world ran clean.
- `localadmin` deliberately NOT in `docker` group (DMZ box) → use `sudo docker`.

### Filesystem — `/srv/aegis/wordpress/` on wp01
```
Dockerfile            (TIER A version below — replace whatever's there with it)
docker-compose.yml    db + wordpress + wpnet; CONFIG_EXTRA holds the 2 defines
.env                  chmod 600 — DB creds (hex) + WP DB creds + PINNED WP salts
.env.template         committed, REPLACE_ME markers
.gitignore            explicit names only (.env, data/) — NO globs
data/db/              bind → /var/lib/mysql
data/uploads/         bind → wp-content/uploads (owned 33:33 = www-data)
```
- Persistent data on vdb via bind mounts so ZFS snapshots capture DB + uploads.
  Images/core on vda (rebuildable). WP salts pinned so rebuilds don't log members out.

### Immutable defines (verified live at runtime, NOT in wp-config text — see §4.2)
- `DISALLOW_FILE_MODS=true`, `AUTOMATIC_UPDATER_DISABLED=true` → confirmed
  `bool(true)` each via `php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA")); var_dump(...)'`.
- Reverse-proxy trust: the official image already ships its own `X-Forwarded-Proto`
  block; our CONFIG_EXTRA proxy lines are redundant (optional trim to the 2 defines
  → zero `$` → immune to the compose `$$` foot-gun).
- `WP_HOME`/`WP_SITEURL` NOT set yet (set at HAProxy step; constants override DB).

---

## 3. REMAINING BUILD PLAN

### STEP 4 — Plugins + child theme, BAKED into the Dockerfile (phased)

**Verified pins (current as of 2026-06-11):**

| Plugin | Pin | Gate |
|---|---|---|
| BuddyPress | 14.3.4 | Label ~6.7–6.8; accepted on SMOKE-TEST basis |
| WP Mail SMTP | 4.8.0 | Smoke-tested clean on 6.9.4 ✓ |

Baking mechanic (authoritative, Docker Hub official image docs): place content in
`/usr/src/wordpress/wp-content/{plugins,themes}/`. The entrypoint copies
`/usr/src/wordpress` → `/var/www/html` on container start, so baked content lands
in the served tree. Baking into `/var/www/html` directly is the wrong location.
Plugin zips: `https://downloads.wordpress.org/plugin/{slug}.{version}.zip`.
`DISALLOW_FILE_MODS` blocks *installing/updating*, NOT *activating* baked plugins.

#### TIER A (DONE ✓) — keystone + mail transport

**RESULT (2026-06-11): gate PASSED.** Built on wp01, all objective checks green —
baked plugins present (`akismet, buddypress, hello.php, index.php, wp-mail-smtp`),
served version `6.9.4`, immutable defines `bool(true)` ×2, no PHP fatals. Smoke
test (scripted via ephemeral wp-cli in the running container): BuddyPress + WP Mail
SMTP activate; Activity + Extended Profiles enable, no 500; "Mailing Address"
xProfile field (ID 2) creates and lists; zero fatals. **One open item deferred to
the configure step** (the `THEN` block, in the real-domain context after Step 5):
BP-12 directory URL rendering — `/activity/` and `/members/<user>/` soft-200 to the
homepage. Root cause is BuddyPress *Rewrites* (BP 12+ routes directories via a
`buddypress` custom post type + WP Rewrite rules, NOT real WP pages), with known
front-page / trailing-slash interactions; a headless `wp rewrite flush` doesn't
fully register the rules. NOT a 6.9.4 fatal. **Fix at configure time, over HTTPS
with `WP_HOME`/`WP_SITEURL` set:** wp-admin → BuddyPress → Settings → URLs; Settings
→ Permalinks → Save (full-context flush); decide static front page; if Rewrites
still fights the setup, evaluate **BP Classic** (neutralizes Rewrites → legacy
page routing). Tier B child theme then styles the BP surfaces. See §4 lesson 6.

**Dockerfile (AS BUILT — keystone plugins + pretty-permalink Apache fix):**
```dockerfile
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

# Pretty permalinks (BuddyPress 12+ rewrites need them). Base Debian Apache sets
# AllowOverride None on /var/www → WP .htaccess ignored → every pretty URL 404s.
# Allow overrides on the docroot, ensure mod_rewrite, bake the standard WP
# .htaccess (entrypoint copies it into the docroot on start). Static + immutable.
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
```

**Deploy (repo = truth; scp transport for now):**
```bash
# Scorpius
cd ~/weirdtable-summercamp
git add Dockerfile && git commit -m "Tier A bake: BuddyPress 14.3.4 + WP Mail SMTP 4.8.0" && git push
scp Dockerfile localadmin@172.22.3.26:/srv/aegis/wordpress/Dockerfile
# wp01
cd /srv/aegis/wordpress
sudo docker compose up -d --build
sudo docker compose exec wordpress ls wp-content/plugins   # expect buddypress + wp-mail-smtp (+ core bundles)
```
(Formalizing wp01 as a git checkout with a read-only deploy key + DMZ_404
outbound-22 rule — ansible01's pattern — is the eventual clean `git pull` loop;
not blocking. scp is fine because the repo already holds the committed truth.)

**Smoke-test the BuddyPress gate — DONE (PASSED, 2026-06-11).** Ran scripted via
wp-cli dropped into the *running* container (image stays immutable; it vanishes on
the next rebuild). Site installed against the IP (title "Summercamp", admin user
`scadmin`) — safe because the `WP_HOME`/`WP_SITEURL` constants set at the HAProxy
step override the DB. Verified: both plugins activate; Activity + Extended Profiles
enable (no 500); "Mailing Address" xProfile field creates + lists; no fatals. The
only sub-step not green is the Activity/member *directory render* — see the Tier A
RESULT note above (BP-Rewrites config, deferred to the configure step).
NOTE for re-runs: `wp bp xprofile field create` is NOT idempotent (re-running adds
a duplicate field); the WP install + DB persist on the bind mount across rebuilds,
but the ephemeral wp-cli does not (re-fetch the phar after each rebuild).

#### TIER B (next) — branding + the security gate
- **TT25 child theme** baked into the image (style.css + theme.json with the
  weirdtable palette/fonts; style the BuddyPress surfaces). COPY a `child-theme/`
  dir from the repo into `/usr/src/wordpress/wp-content/themes/`. Frontend work —
  good Claude Code lane; use the frontend-design skill.
- **Invite-only registration gate** (the Domino root-cause fix) — Paid Memberships
  Pro free core OR a dedicated invite-code plugin; confirm the exact plugin +
  approach at build time (plugins churn). Enforce: no open signup, login-required
  to post/comment.
- **Hardening MU-plugin** (auto-active, can't be disabled): strip generator meta,
  kill xmlrpc, block REST user enumeration for logged-out requests (conditional —
  don't break the block editor for logged-in users), redirect author archives.
  Verify it doesn't break BuddyPress member pages.
- **Akismet** activation (likely bundled in core image) — spam defense-in-depth.

#### TIER C (later) — event workflow
- Address CSV export (xProfile → CSV → LibreOffice mail merge).
- RSVP/forms plugin (capture RSVP + confirmation email).
- Optional newsletter plugin (broadcast/merge mail).
- Pick concrete free plugins + verify each tested-up-to ≥ 6.9 at build time.

### STEP 5 — HAProxy on OPNsense + WAN rule + Unbound override (no CLI surface — do in the chat window)
- Five-object pattern (Real Server → Backend → Condition hdr_beg host=`summercamp`
  → Rule → Public Service), terminate TLS by SNI → wp01:80. WAN TCP/443 rule to VIP
  + Unbound override `summercamp.weirdtable.org` → WAN VIP (internal hairpin).
- Lock `/wp-admin` + `/wp-login.php` to trusted source IPs (LAN-only, not Wi-Fi).
- Header hardening: del X-Powered-By / X-Pingback / `Link ...api.w.org`;
  ACL-block `/xmlrpc.php`, `/wp-json/wp/v2/users`, `/?author=`, `/readme.html`, `/license.txt`.
- Set `WP_HOME`/`WP_SITEURL` = `https://summercamp.weirdtable.org` (heredoc/sed, mind `$$`).

### STEP 6 — TLS
- OPNsense ACME (Cloudflare DNS-01), subject `summercamp.weirdtable.org`, HAProxy
  serves it. Publish Cloudflare A → WAN VIP. Use the per-zone `CF_DNS_weirdtable` token.

### THEN
- **Finish BP-12 directory routing (carried from Tier A).** Over HTTPS with
  `WP_HOME`/`WP_SITEURL` set: wp-admin → BuddyPress → Settings → URLs; Settings →
  Permalinks → Save (full-context flush — headless `wp rewrite flush` wasn't
  enough); decide static front page (BP Rewrites has a known front-page conflict);
  retest `/activity/` + `/members/<user>/` render real BP markup (not a soft-200 to
  the homepage). If Rewrites still fights it → activate **BP Classic** (legacy
  page routing). See §3 Tier A RESULT + §4 lesson 6.
- Configure plugins, BuddyPress xProfile address fields, invite gate, WP Mail SMTP → Mailcow.
- Mailcow tie-in: create `summercamp@weirdtable.org` (or pending `noreply@`) for site outbound.

---

## 4. LESSONS (carry-in)

1. **Literal `$` in a docker-compose VALUE must be doubled to `$$`.** Compose
   interpolates YAML values before the container sees them. Unescaped `$_SERVER`
   in `WORDPRESS_CONFIG_EXTRA` → `WARN "_SERVER" variable is not set` + malformed
   inject → HTTP 500. Sibling to Aegis gotcha #14.
2. **The official `wordpress` image `eval()`s `WORDPRESS_CONFIG_EXTRA` at runtime;
   it does NOT append it to wp-config.php.** So grepping wp-config.php for your
   defines returns nothing even when live. Verify at runtime:
   `docker compose exec wordpress php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA")); var_dump(DISALLOW_FILE_MODS, AUTOMATIC_UPDATER_DISABLED);'`
3. **Bake plugins/themes into `/usr/src/wordpress/wp-content/`, not `/var/www/html`.**
   The entrypoint copies the former to the latter on start. `DISALLOW_FILE_MODS`
   blocks install/update but not activation of baked plugins.
4. **"Tested up to" is a label, not a verdict.** For a keystone with a lagging
   label (BuddyPress), the real gate is a functional smoke test in the image, not
   the wordpress.org number. For everything else the label is a fine first filter.
5. **Docker's official apt repo has a real `trixie` channel** (Docker CE 29.x) —
   no codename hack on Debian 13.
6. **BuddyPress 12+ routes directories via a `buddypress` custom post type + WP
   Rewrites, NOT real WP pages.** So `bp-pages` IDs won't appear in
   `wp post list --post_type=page` (they're the CPT), and `bp_core_add_page_mappings()`
   is the wrong lever to "create pages." Symptom of a broken setup: directory URLs
   (`/activity/`, `/members/`) **soft-200 to the homepage** (body byte-identical to
   `/` → catch it by diffing body size, not just the HTTP code). A headless
   `wp rewrite flush` doesn't fully register BP's rules; the reliable fix is a
   full-context flush (wp-admin Settings → Permalinks → Save) once on the final
   domain, or **BP Classic** to fall back to legacy page routing.
7. **Pretty permalinks need AllowOverride on the official wordpress:apache image.**
   Base Debian Apache ships `AllowOverride None` on `/var/www`, so WP's `.htaccess`
   rewrite rules are ignored and EVERY pretty URL 404s (not just BP). Bake an
   `AllowOverride All` conf for the docroot + `a2enmod rewrite` + a static
   `.htaccess` into `/usr/src/wordpress/`. Distinguish this Apache 404 (server
   error page) from a WP 404 (themed "Page not found") when diagnosing.
8. **wp-cli for one-off ops: drop the phar into the RUNNING container, not the
   image** (`curl … wp-cli.phar -o /usr/local/bin/wp`); run it as `-u www-data` with
   `HOME=/tmp WP_CLI_CACHE_DIR=/tmp`. Keeps the image immutable; re-fetch after each
   rebuild (the writable layer is discarded). DB + uploads persist (bind mounts).

---

## 5. wp01 FACTS

- libvirt domain `wordpress` (lowercase). Linux hostname `wordpress`. Future
  Ansible inventory `wp01`, group `web_servers`.
- Debian 13 Trixie, 2 vCPU / 4 GB. VLAN 404 (DMZ_404), `172.22.3.26/29`,
  gw `172.22.3.25`. NOT AD-joined.
- `vda` 40G OS; `vdb` 60G Services → ext4 `/srv/aegis` `defaults,discard`.
  UUID `633fac30-e30a-480b-b6b9-31dcb2518747`.
- Public DNS service name: `summercamp.weirdtable.org` (legacy FQDN reused;
  DNS-only + HAProxy SNI; ≠ box hostname; = ACME cert subject + SNI match value).
- Camp accounts = WordPress-LOCAL, NOT AD/LDAP. Invite-gated, WP-local.

---

## 6. ENVIRONMENT / DEPLOY NOTES

- **Claude Code runs on the trusted side (Scorpius), NOT on wp01** (DMZ).
- Scorpius → wp01 is SSH **key-auth** (ed25519); `sudo` on wp01 still prompts (correct).
- **Privileged-step workflow (sudo can't go through Claude's Bash tool — no TTY).**
  Claude stages scripts on wp01 via `scp` (checksum-verify both ends). The USER runs
  the privileged build/test in their own terminal: `ssh -t localadmin@172.22.3.26
  'bash /srv/aegis/wordpress/<script>.sh 2>&1 | tee /tmp/<name>.log'` (one sudo
  prompt; sudo caches for the rest). Then Claude reads results **non-privileged**:
  `ssh localadmin@172.22.3.26 'cat /tmp/<name>.log'` — no copy-paste. The `!`-prefix
  in Claude's prompt does NOT allocate a TTY, so sudo prompts fail there; use a real
  terminal. localadmin is intentionally out of the `docker` group, so docker needs
  `sudo` (kept; don't add NOPASSWD or the docker group on this DMZ box without cause).
- Deploy path now: edit in repo → commit/push → `scp` file(s) to wp01 → rebuild.
  Future: wp01 read-only deploy key + DMZ_404 outbound-22 → `git pull` loop.
- BuildKit can serve a stale image — verify the running version via the app, not
  Docker's "Started" line.
- One driver per task: don't have two agents authoring the same file in parallel.
