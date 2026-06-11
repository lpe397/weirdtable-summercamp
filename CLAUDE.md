# WORDPRESS ON wp01 — BUILD SEED / CLAUDE.md (v3)

**Status:** Skeleton VALIDATED (Docker, WP 6.9.4, MariaDB 11.4, immutable defines
live). **Mid step 4 (tier A):** plugins pinned, tier-A Dockerfile written below,
NOT yet built/deployed/smoke-tested. NOT done beyond that: child theme,
hardening MU-plugin, registration gate, event-workflow plugins, HAProxy/TLS/DNS,
git-based deploy loop to wp01.
**Date:** 2026-06-11
**Parent project:** Summercamp (self-hosted site to replace the Facebook group)
**Supersedes:** the parked v1 seed (full functional spec / Domino narrative lives
there — read it for the "why").

---

## 0. HOW TO USE / CURRENT TASK FOR CLAUDE CODE

This file is the project memory. Interaction Preferences from the Aegis seed apply
(direct, objective, sudo on admin cmds, delta edits, verify versions before
asserting, one step at a time, challenge bad ideas, no epicycles).

**CURRENT TASK = TIER A ONLY.** Bake **BuddyPress + WP Mail SMTP** (just those two),
deploy to wp01, and smoke-test BuddyPress on 6.9.4. **Do NOT bake the full plugin
set in one shot** — the tiering below exists to isolate the one real unknown
(does BuddyPress run on 6.9.4). Tiers B and C come in later rebuilds.

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

#### TIER A (CURRENT) — keystone + mail transport

**Dockerfile (replace the thin one):**
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

**Smoke-test the BuddyPress gate (this is the accepted decision — actually run it).**
Installing now against the IP is safe: the `WP_HOME`/`WP_SITEURL` constants set at
the HAProxy step override whatever the installer writes, so it self-corrects.
1. Browser → `http://172.22.3.26/wp-admin/install.php` → install (title "Summercamp", make admin user).
2. Plugins → activate **BuddyPress** + **WP Mail SMTP**.
3. Settings → BuddyPress → Components: enable Activity + Extended Profiles, save (no 500).
4. Visit Activity page — renders. Users → Profile Fields → add "Mailing Address" — saves, shows on a member profile.
5. `sudo docker compose logs --tail=50 wordpress` — no PHP fatals.
PASS all → 14.3.4 runs clean on 6.9.4, gate satisfied, proceed to tier B. Any fatal → stop, capture the log line.

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
- Deploy path now: edit in repo → commit/push → `scp` file(s) to wp01 → rebuild.
  Future: wp01 read-only deploy key + DMZ_404 outbound-22 → `git pull` loop.
- BuildKit can serve a stale image — verify the running version via the app, not
  Docker's "Started" line.
- One driver per task: don't have two agents authoring the same file in parallel.
