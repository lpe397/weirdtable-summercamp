# WORDPRESS ON wp01 — BUILD SEED (v2 / continuation)

**Status:** Skeleton stack VALIDATED and running on wp01. Docker CE installed;
WordPress 6.9.4 + MariaDB 11.4 compose stack up; DB healthy; site serves
(`/` → 302 to installer, `install.php` → 200). Immutable-model defines confirmed
live at runtime. NOT yet done: child theme + plugins baked, HAProxy/TLS/DNS,
browser install, git init.
**Date parked:** 2026-06-11
**Parent project:** Summercamp (self-hosted site to replace the Facebook group)
**Supersedes:** `WordPress_wp01_Build_SEED.md` (v1, parked 2026-06-08). v1 still
holds the full functional spec / Domino-disaster narrative — read it for the
"why"; this doc holds validated state + next actions.

---

## 0. HOW TO USE
Drop this in the `weirdtable-summercamp` repo dir (or fold into the repo's own
`CLAUDE.md` so terminal Claude Code auto-loads it). Do NOT mix into the Aegis
`CLAUDE.md` pile — the separate-repo decision exists to keep this self-contained.
Interaction Preferences from the Aegis seed apply (direct, objective, sudo on
admin cmds, delta edits, verify versions, one step at a time, challenge bad ideas).

---

## 1. DECISIONS LOCKED (do NOT relitigate)

- **WordPress 6.9 branch, NOT 7.0.** 7.0 shipped 2026-05-20 (~3 weeks old at
  parking). Stability-first for a low-touch site + BuddyPress block-compat is
  weakest on a brand-new core major. 6.9→7.x is a *deliberate, snapshot-protected
  rebuild* once the plugin ecosystem has tested against 7.0 — on our schedule.
- **Theme: Twenty Twenty-Five + a child theme.** Dispositive reason: TT25 is
  bundled inside WP core, so it can NEVER be the thing that blocks a security
  patch. A third-party theme can lag a core release → can block a patch →
  violates security-#1. Cost accepted: CSS work to style the BuddyPress surfaces
  (feed/profiles/member directory), since BP block-theme rendering is "improving
  but not complete." TT25 also needs no separate download/pin — it's in the base
  image. **BuddyX rejected** (looks finished faster, but third-party dependency =
  the exact risk we're avoiding).
- **Repo: separate private repo `weirdtable-summercamp` under `lpe397`**, NOT the
  Aegis monorepo. Offboarding-first; treat weirdtable as a client. Git wired
  AFTER the stack validates (i.e. now).
- **MariaDB = its own container (`mariadb:11.4`), NOT db01.** db01 stays
  single-purpose MyISAM-for-OpenDental.
- **No Traefik.** Single app; HAProxy on OPNsense terminates TLS, forwards to
  wp01:80. (Traefik was right for mgmt01's multi-tile future, wrong here.)

---

## 2. VALIDATED STATE (what's actually built + verified)

### Docker
- Docker CE from Docker's official apt repo, **DEB822 `.sources` format**, suite
  `trixie`, component `stable`. (Docker's repo has a real `trixie` channel — no
  codename-substitution hack needed. Docker CE 29.x, compose plugin reported
  `v5.1.4`.) `hello-world` ran clean.
- Decision pending/owner's call: `localadmin` deliberately NOT added to `docker`
  group (passwordless-root-equivalent on a DMZ box). Using `sudo docker`.

### Filesystem layout — `/srv/aegis/wordpress/`
```
Dockerfile            FROM wordpress:6.9-apache (→ 6.9.4, digest sha256:5d2c2125...)
docker-compose.yml    db + wordpress + wpnet bridge
.env                  chmod 600 — DB creds (hex) + WP DB creds + PINNED WP salts
.env.template         committed, REPLACE_ME markers, no secrets
.gitignore            explicit names only (.env, data/) — NO globs (the *password* lesson)
data/db/              bind → /var/lib/mysql (localadmin-owned; mariadb chowns to mysql on init)
data/uploads/         bind → wp-content/uploads (owned 33:33 = www-data)
```
- **Persistent data lives on vdb (/srv/aegis) via bind mounts** so ZFS snapshots
  on the hypervisor capture DB + uploads. Images/core stay on vda (rebuildable).
- **WP salts pinned in `.env`** so rebuilds don't log every member out.

### Dockerfile (current = thin)
- `FROM wordpress:6.9-apache` only. Comment placeholder for child-theme + plugin
  bake (step 4). Parent theme TT25 already inside the base image.

### docker-compose.yml (current)
- `db`: `mariadb:11.4`, `restart: unless-stopped`, `env_file: .env`, utf8mb4
  charset/collation, bind `./data/db`, healthcheck via `healthcheck.sh
  --connect --innodb_initialized`, **no published ports** (reachable only as
  `db:3306` on `wpnet`).
- `wordpress`: `build: .`, `depends_on: db (service_healthy)`, `env_file: .env`,
  `environment: WORDPRESS_CONFIG_EXTRA` (see below), bind `./data/uploads`,
  **publishes `80:80`** for OPNsense/HAProxy, on `wpnet`.
- `WP_HOME` / `WP_SITEURL` **deliberately NOT set yet** — hardcoding the public
  FQDN now breaks the localhost bring-up test. Set them at the HAProxy step.

### WORDPRESS_CONFIG_EXTRA (verified live)
- Contains: `DISALLOW_FILE_MODS=true`, `AUTOMATIC_UPDATER_DISABLED=true` — both
  confirmed `bool(true)` at runtime. These make wp-admin's installer inert; baking
  is the only install path (correct for immutable model).
- Also still contains a redundant `X-Forwarded-Proto` proxy block. **Redundant** —
  the official image already ships its own proxy block (see Lessons). Optional
  cleanup: trim CONFIG_EXTRA to just the two defines → zero `$` → immune to the
  `$$` foot-gun. Not yet done.

---

## 3. REMAINING BUILD PLAN (in order)

### Step 4 — Bake child theme + pinned plugins into the Dockerfile
Check each plugin's "tested up to" is **≥ 6.9** before it goes in. Bake at PINNED
versions in the Dockerfile, NOT via wp-admin (DISALLOW_FILE_MODS blocks that path
anyway). Target set (all free — see v1 seed for rationale):
- **BuddyPress** — activity feed (FB-style) + **xProfile extended fields =
  member-editable mailing-address directory**. The keystone plugin.
- **Paid Memberships Pro** (free core) — invite-gate / login-required. Confirm the
  exact invite-code approach in-session (plugins churn).
- **WP Mail SMTP** (free) — route ALL site mail through existing Mailcow
  (authenticated submission 465/587) so outbound rides weirdtable.org DKIM/SPF/DMARC.
- **Akismet** (free personal) — spam defense-in-depth.
- A free **user/profile CSV-export** plugin — address export → LibreOffice mail
  merge (replaces NotesSQL→Word).
- A free **RSVP/forms** plugin — capture RSVP + send confirmation.
- (Optional) a free **newsletter** plugin — merge-blasts to attendees.
- Child theme: pour in weirdtable brand (parchment `#f5ecd6`, forest green
  `#306000`, brass, Cinzel + EB Garamond) via `theme.json` / child-theme CSS,
  including the BuddyPress surfaces. Baked, not installed at runtime.

### Step 5 — HAProxy on OPNsense + WAN rule + Unbound override
- Standard **five-object pattern** (Real Server → Backend → Condition (hdr_beg
  host = `summercamp`) → Rule → Public Service), terminate TLS by SNI, forward to
  **wp01:80**. Plus WAN TCP/443 rule to the VIP + Unbound host-override
  `summercamp.weirdtable.org` → WAN VIP for internal hairpin.
- **Lock `/wp-admin` + `/wp-login.php` to trusted source IPs** via HAProxy ACL —
  public gets the site; admin surface answers LAN-only (not even Wi-Fi).
- Header hardening: `del-header X-Powered-By`, `del-header X-Pingback`, strip
  `Link: ...api.w.org`. ACL-block from public: `/xmlrpc.php`,
  `/wp-json/wp/v2/users`, `/?author=`, `/readme.html`, `/license.txt`.
- Set `WP_HOME` / `WP_SITEURL` = `https://summercamp.weirdtable.org` NOW (via
  CONFIG_EXTRA or env). Edit with heredoc/sed, not nano-paste (gotcha #14); mind
  `$$` if any `$` sneaks in.
- NO cert-deploy pipeline to wp01 — cert stays on OPNsense/HAProxy.

### Step 6 — TLS
- OPNsense ACME (Cloudflare DNS-01) issues cert, subject
  `summercamp.weirdtable.org`. HAProxy serves it. Publish Cloudflare A record →
  WAN VIP. Use the per-zone `CF_DNS_weirdtable` token.

### Then
- Browser install (URL is finally correct), configure plugins, BuddyPress
  xProfile address fields, PMPro invite gate, WP Mail SMTP → Mailcow, theme brand.
- **Mailcow tie-in:** create `summercamp@weirdtable.org` (or the already-pending
  `noreply@weirdtable.org`) mailbox/alias for site outbound. Ties to the pending
  noreply@ task in the Aegis seed.
- **Git:** `git init` the repo, push validated config. `.env` + `data/` already
  gitignored. Push to `github.com/lpe397/weirdtable-summercamp` (separate repo).

---

## 4. LESSONS EARNED THIS SESSION (carry-in)

1. **Literal `$` in a docker-compose VALUE must be doubled to `$$`.** Compose
   interpolates YAML values before the container sees them. An unescaped
   `$_SERVER` in `WORDPRESS_CONFIG_EXTRA` → `WARN "_SERVER" variable is not set`
   and a malformed PHP inject → HTTP 500 on every page. Sibling to gotcha #14:
   a layer you didn't think was interpolating is interpolating.
2. **The official `wordpress` image does NOT append `WORDPRESS_CONFIG_EXTRA` to
   `wp-config.php` — it `eval()`s it at runtime** (`if ($configExtra =
   getenv_docker('WORDPRESS_CONFIG_EXTRA','')) { eval($configExtra); }`). So
   grepping `wp-config.php` for your defines returns NOTHING even when they're
   fully live. This produced a false-negative "the defines didn't land" scare —
   they were always applying. **Verify at runtime, not in the file:**
   `docker compose exec wordpress php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA"));
   var_dump(DISALLOW_FILE_MODS, AUTOMATIC_UPDATER_DISABLED);'` → expect
   `bool(true)` ×2.
3. **The official image already ships its own `X-Forwarded-Proto` reverse-proxy
   block** by default ("included by default because reverse proxying is extremely
   common in container environments"). A custom proxy snippet in CONFIG_EXTRA is
   redundant. Keep CONFIG_EXTRA to the immutable defines only → zero `$` → can't
   trip lesson 1.
4. **Docker's official apt repo has a real `trixie` channel** (Docker CE 29.x) —
   no codename-substitution hack on Debian 13.

---

## 5. wp01 FACTS (carry from v1, confirmed)

- **libvirt domain:** `wordpress` (lowercase). **Linux hostname:** `wordpress`.
  **Future Ansible inventory:** `wp01`, group `web_servers`.
- **OS:** Debian 13 Trixie, 2 vCPU / 4 GB.
- **Network:** VLAN 404 (DMZ_404), `172.22.3.26/29`, gw `172.22.3.25`. NOT
  AD-domain-joined (DMZ standalone). DNS + internet confirmed.
- **Disks:** `vda` 40G OS; `vdb` 60G Services → ext4, mounted `/srv/aegis`,
  `defaults,discard`. UUID `633fac30-e30a-480b-b6b9-31dcb2518747`. ~56G avail.
- **Public DNS service name:** `summercamp.weirdtable.org` (the legacy FQDN,
  reused so old merch URLs resolve). DNS-only + HAProxy SNI; ≠ box hostname. This
  is the ACME cert subject and the HAProxy SNI match value.
- **Auth model:** camp accounts = **WordPress-LOCAL, NOT AD/LDAP** (party guests,
  not weirdtable infra identities). Invite-gated, WP-local.

---

## 6. CLAUDE CODE HANDOFF NOTES

- Run terminal Claude Code on the **trusted side (Scorpius / workstation), NOT on
  wp01** — wp01 is a DMZ host; an agentic sudo shell there contradicts Zero-Trust
  minimal-DMZ-surface. Claude Code works the repo + (eventually) the `wordpress`
  Ansible role and pushes to wp01 via git/ssh.
- Claude Code can't do the **OPNsense half** (HAProxy five-object, ACME) — those
  are web-GUI. Keep this chat (or any GUI-aware flow) for steps 5–6.
- Keep it on a short leash (review-before-run) — matches the deliberate,
  verify-each-step working style.

---

## 7. QUICK VERIFY (rehydrate state on wp01)

```bash
cd /srv/aegis/wordpress
sudo docker compose ps                      # db healthy, wordpress up, 80->80
curl -sI http://localhost/ | head -1        # HTTP 302
curl -sI http://localhost/wp-admin/install.php | head -1   # HTTP 200
sudo docker compose exec wordpress sh -c 'grep "\$wp_version =" wp-includes/version.php'  # 6.9.4
sudo docker compose exec wordpress php -r 'eval(getenv("WORDPRESS_CONFIG_EXTRA")); var_dump(DISALLOW_FILE_MODS, AUTOMATIC_UPDATER_DISABLED);'  # bool(true) x2
```
