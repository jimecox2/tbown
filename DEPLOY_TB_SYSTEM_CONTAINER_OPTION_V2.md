# Deploy the Timebars System — Container Option, V2

One person (the **dev**) owns the configuration of every environment. On a dev box, in VS Code, they fill in
one file, `tbapps.conf`, and run one command. That makes a ready-to-deploy folder per environment. The dev
stands up DEV on the dev box and tests it, then each other folder (STAGING, PROD, TRAINING) goes to its
server and is started with the same command.

```text
 dev box (VS Code, tbown clone)                          servers
 tbapps.conf ── bash scripts/apply.sh ──► envs/DEV       ./deploy-all.sh on the dev box itself
                                          envs/STAGING ─► staging server  ./deploy-all.sh
                                          envs/PROD    ─► production      ./deploy-all.sh
                                          envs/TRAINING ► training server ./deploy-all.sh
```

*V1 (one settings file per server, `scripts_v1/`) is in `DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V1.md`.*

## Contents

1. [What you need](#1-what-you-need)
2. [Set up the dev box](#2-set-up-the-dev-box)
3. [Fill in tbapps.conf and apply it](#3-fill-in-tbappsconf-and-apply-it)
4. [Deploy DEV on the dev box](#4-deploy-dev-on-the-dev-box)
5. [After every first deploy](#5-after-every-first-deploy)
6. [Deploy STAGING, PROD and TRAINING](#6-deploy-staging-prod-and-training)
7. [Your own proxy](#7-your-own-proxy)
8. [Keys and passwords](#8-keys-and-passwords)
9. [Changes, updates and rollback](#9-changes-updates-and-rollback)
10. [Backups and restore](#10-backups-and-restore)
11. [Troubleshooting](#11-troubleshooting)

## 1. What you need

| Item | Notes |
|---|---|
| **Dev box** | Ubuntu 24.04 or 26.04 desktop or server, 2+ cores, 8 GB RAM, 100 GB disk; VS Code, `git`, `python3`, `rsync`. You run DEV on it. |
| **One server per other environment** | Ubuntu 24.04 or 26.04, 2+ cores, 4 GB RAM (with swap), 100 GB disk, patched under your policies; an admin user with `sudo` and SSH key login; `python3`, `rsync`, `curl`; outbound internet to Docker Hub. |
| **Docker Hub access** | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token |
| **Names** | six per environment (three apps, backend, website, Cloud), made from your domain — `apply` lists them for your DNS team |
| **Keys (optional)** | Google Gemini (AI), SendGrid (email), Stripe (only if you sell licences) — [section 8](#8-keys-and-passwords) |

The containers in every environment:

| Container | What it does |
|---|---|
| `tbpgdb` | PostgreSQL database for Strapi |
| `tbbe` | Strapi backend: login, licences, publishing, registration email |
| `tbwwwp` | website: sales, sign-up, profile, orders |
| `tbhelpapp` | Timebars Cloud (dashboards, notifications) and the AI service |
| `tbrun` | the Agilebars / Timebars / Costbars app (works offline after the first visit) |
| `tbproxy` | Caddy: answers every name over HTTPS — skipped when you use your own proxy |

One environment runs per machine. Only the proxy is reachable from the network (ports 80 and 443); the
other containers listen on the machine itself (`127.0.0.1`).

## 2. Set up the dev box

In a terminal on the dev box:
```bash
sudo apt install -y git python3 rsync
git clone https://github.com/jimecox2/tbown.git ~/tbown
code ~/tbown                                   # open it in VS Code
```
Everything from here runs in VS Code's integrated terminal (*Terminal → New Terminal*), in `~/tbown`.

Install Docker once and log in to Docker Hub:
```bash
sudo bash templates/scripts/install-docker.sh  # then log out of the desktop and back in
docker login -u <your Docker Hub user>         # paste your read-only access token
```

## 3. Fill in tbapps.conf and apply it

```bash
cp tbapps.conf.example tbapps.conf             # never committed: .gitignore keeps it out
```
Open `tbapps.conf` in VS Code. `[ALL]` is shared; each section below it makes one environment. Delete
the sections you do not need.

| Setting | Where | What |
|---|---|---|
| `DOMAIN` | `[ALL]` | e.g. `example.com`. Names are `agile`, `pmrm`, `ppm`, `be2`, `www`, `cloud` + `NAME_SUFFIX` + `.DOMAIN` |
| `NAME_SUFFIX` | each env | `d` → `agiled.example.com`; empty for PROD → `agile.example.com`. Or set any name exactly (`APP_AB_HOST=` …) |
| `SERVER_IP` | each env | the address the names point at (the proxy) |
| `PROXY` | each env | `caddy` = our proxy container; `own` = your proxy ([section 7](#7-your-own-proxy)) |
| `TLS` | each env | `letsencrypt` = public names, ports 80/443 open to the internet; `internal` = Caddy's own certificates, for names only in hosts files or internal DNS |
| `ACME_EMAIL`, `EMAIL_FROM` | `[ALL]` | certificate notices; sender of registration emails |
| `GEMINI_API_KEY`, `SENDGRID_API_KEY` | optional | recommended: leave empty here ([section 8](#8-keys-and-passwords)) |

Then:
```bash
bash scripts/apply.sh --check                  # checks the file, writes nothing
bash scripts/apply.sh                          # makes envs/DEV, envs/STAGING ...
```
Each `envs/<ENV>` folder is complete: the stack folders with their settings, `proxy/Caddyfile`, `secrets.env`,
the seed data, the scripts, and **`DEPLOY.md`** — that environment's names, the DNS records to request, the
routes for your own proxy, and its deploy steps. Open them in VS Code and check them. Small changes
(a name, an address) are a find and replace in the folder; `apply` runs once ([section 9](#9-changes-updates-and-rollback)).

**Send each `envs/<ENV>/DEPLOY.md` table *Names* to your DNS team now**, so the records exist when you deploy.

## 4. Deploy DEV on the dev box

DEV's names can be real DNS records or lines in a hosts file. For the dev box itself, add them pointing at
`127.0.0.1` (other machines use the dev box's address, `envs/DEV/DEPLOY.md` lists them):
```bash
grep '^[0-9]' envs/DEV/DEPLOY.md | awk '{print "127.0.0.1  " $2}' | sudo tee -a /etc/hosts
```
Deploy:
```bash
cd envs/DEV
nano secrets.env                               # optional: paste keys (Gemini, SendGrid) - passwords are made for you
./deploy-all.sh
```
`deploy-all.sh` makes the passwords, the Docker network and volumes, starts every container in order with
the tags in `VERSION.md`, loads the seed data on the first run, starts the proxy and runs the health check.
Run it again any time: it keeps passwords and data and recreates only what changed.

With `TLS=internal`, trust Caddy's certificate on each browser machine once (needed for HTTPS without
warnings and for offline mode):
```bash
docker cp tbproxy:/data/caddy/pki/authorities/local/root.crt caddy-root.crt
sudo cp caddy-root.crt /usr/local/share/ca-certificates/timebars-dev.crt && sudo update-ca-certificates
```
Browsers with their own list (Firefox; Chrome on Linux): *Settings → Certificates → Authorities → Import*
`caddy-root.crt`. On Windows: double-click it → *Install* → *Trusted Root Certification Authorities*.

Check every name from outside the containers:
```bash
bash scripts/check-urls.sh
```

## 5. After every first deploy

The same steps in every environment, in its folder:

1. **Strapi admin password.** The seed brings Timebars Ltd.'s admin accounts. Set your own:
   ```bash
   docker exec tbpgdb psql -U strapi -d strapi -Atc "select email from admin_users"
   docker exec -it tbbe strapi admin:reset-user-password    # asks the email, then the new password
   ```
2. **Strapi API token** (the website and Cloud need it). Open `https://<backend name>/admin` → *Settings* →
   *API Tokens* → **Create new API token**: name `<ENV>-server`, *Unlimited*, *Full access*. Copy it into
   `secrets.env` as `STRAPI_ADMIN_TOKEN=`, then `./deploy-all.sh`.
3. **Browser check.** Open each app name (the product matches the name), sign in with a demo account, check
   *Show License*, publish a dataset and open it on the dashboard, ask the help assistant a question.
4. **Nightly backup** ([section 10](#10-backups-and-restore)).

## 6. Deploy STAGING, PROD and TRAINING

Every environment is deployed the same way. Before you start: the DNS records from its `DEPLOY.md` exist and
point at the server, and (with `PROXY=caddy`) ports 80 and 443 reach it.

**a. Get the folder to the server.** The customer's process decides; these are the usual ways:

| Way | How |
|---|---|
| **Recommended:** the dev gets temporary SSH access and pushes it | `cd envs/PROD && ./push.sh <server> /srv/timebars/PROD` |
| IT takes a package | `cd envs/PROD && ./push.sh --tar` → `envs/PROD-<date>.tar.gz`; on the server `tar xzf` it |
| IT copies the folder its own way | any copy of `envs/PROD` works; leave out nothing |

`push.sh` needs an SSH shortcut on the dev box (`~/.ssh/config`: `Host`, `HostName`, `User`, `IdentityFile`,
`IdentitiesOnly yes`) and key login (`ssh-copy-id <server>`). Run it again after a change: it never
overwrites what belongs to the server (its passwords, running tags, uploaded files). If the folder's parent
belongs to root, it prints the one `sudo` command to run there first.

**b. On the server**, in that folder, as the admin user (no sudo):
```bash
sudo bash scripts/install-docker.sh            # once per server, then log out and back in
docker login -u <Docker Hub user>              # once per server, read-only token
nano secrets.env                               # paste this environment's keys
./deploy-all.sh
bash scripts/check-urls.sh
```
Then [section 5](#5-after-every-first-deploy).

**Per environment:**

| | STAGING | PROD | TRAINING |
|---|---|---|---|
| Stripe keys | sandbox `sk_test_` / `pk_test_` | live `sk_live_` / `pk_live_` | sandbox, or none |
| Search engines | kept out (`noindex`) | indexed | kept out |
| Seed data | loaded on the first deploy | loaded on the first deploy | loaded on the first deploy |

Every environment starts from the seed. What you load into it afterwards (your own backup, a copy of PROD)
is up to you: `bash scripts/restore.sh <dump> <uploads>` ([section 10](#10-backups-and-restore)).

## 7. Your own proxy

Set `PROXY=own` for the environment (before `apply`, or `PROXY=own` in its `environment.env`).
`deploy-all.sh` then starts everything except Caddy. Your proxy terminates HTTPS for each name and passes
it on over HTTP. `DEPLOY.md` section *Routes* has the table for that environment, for example:

| Name | Proxy on the same server | Proxy as a container on network `tbnet` |
|---|---|---|
| the three app names | `http://127.0.0.1:8687` | `http://tbrun:80` |
| backend | `http://127.0.0.1:1337` | `http://tbbe:1337` |
| website | `http://127.0.0.1:3001` | `http://tbwwwp:3001` |
| Cloud | `http://127.0.0.1:3010` | `http://tbhelpapp:3010` |

Keep the `Host` header, send `X-Forwarded-Proto: https`, and do not cache `/index.html`, `/sw.js` or
`/runtime-config.json`. A proxy on another machine cannot reach `127.0.0.1`: run it on this server, or as a
container joined to `tbnet` (`docker network connect tbnet <your proxy container>`).

## 8. Keys and passwords

| What | Made by | Lives in |
|---|---|---|
| Addresses, names, routes | `apply` on the dev box | each stack's `.env.local`, `tbrun/runtime-config.json`, `proxy/Caddyfile` — no secrets, safe to read and review |
| Keys: Gemini, SendGrid, Stripe, Strapi API token | you paste them | `secrets.env` of that environment |
| Database passwords and sign-in secrets | `deploy-all.sh`, on the machine the environment runs on, the first time | `secrets.env` of that environment |

**What we recommend:** leave the keys out of `tbapps.conf`. The folder you hand over then holds no secret
at all; the passwords are made on the server and never leave it, and the keys are pasted there by whoever
deploys. Keep a copy of each server's `secrets.env` in your password vault.

Where to get the keys:

| Key | Where |
|---|---|
| `GEMINI_API_KEY` | [aistudio.google.com](https://aistudio.google.com) → *Get API key*. Restrict it to the *Generative Language API*; add billing and a budget alert if you expect more than the free tier. Empty = AI off |
| `SENDGRID_API_KEY` | [SendGrid](https://www.twilio.com/en-us/sendgrid) → verify your `EMAIL_FROM` sender → *API Keys* → *Restricted Access* with *Mail Send* (starts with `SG.`). Empty = no email |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` | [dashboard.stripe.com](https://dashboard.stripe.com) → *Developers* → *API keys* (sandbox for everything but PROD). Empty = no checkout |
| `STRAPI_ADMIN_TOKEN` | made after the first deploy ([section 5](#5-after-every-first-deploy)) |

After changing `secrets.env`: `./deploy-all.sh` (it recreates the containers that use it). Never change a
database password in `secrets.env` after the first deploy: the database keeps the one it was created with.

## 9. Changes, updates and rollback

| What | How |
|---|---|
| A name or setting in one environment | dev box: find and replace in `envs/<ENV>` (VS Code), push again, `./deploy-all.sh` on the server |
| A big change (new domain, new environment) | edit `tbapps.conf`, `bash scripts/apply.sh` (new environments) or `--force <ENV>` (makes it again; keeps `secrets.env`; replaces your hand edits) |
| New release | dev box: `git pull`, `bash scripts/apply.sh --force <ENV>` for each environment (new `VERSION.md` and scripts), push, `./deploy-all.sh`; back up first |
| One container to another tag, or roll back | in the environment folder: `cd <stack> && ./deploy.sh` and type the tag (it shows the one running now) |

## 10. Backups and restore

```bash
bash scripts/backup.sh                         # try it once, in the environment folder
crontab -e                                     # then nightly, with the full path of the folder:
# 15 2 * * * /bin/bash /srv/timebars/PROD/scripts/backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup (`~/backups/timebars/<date>`) holds the Strapi database, its uploads, `secrets.env` and the
settings files. Copy that folder off the server with your normal backup system. Restore:
```bash
bash scripts/restore.sh ~/backups/timebars/<date>/strapi.dump ~/backups/timebars/<date>/uploads.tar.gz
```
Users' own project data lives in their browsers; their backup files and synced spreadsheets belong in your
document management system.

## 11. Troubleshooting

`bash scripts/health-check.sh` (inside) and `bash scripts/check-urls.sh` (through the proxy) say what is
wrong in most cases.

| Symptom | Fix |
|---|---|
| `permission denied ... docker.sock` | log out and back in after `install-docker.sh` |
| `Pull failed` | `docker login` with an account that has pull access; check the tag in `VERSION.md` |
| `Ports 80/443 are already in use` | another web server runs on this machine: stop it, or set `PROXY=own` |
| `check-urls.sh`: 000 for a name | the name does not point at the proxy (DNS or hosts file), ports 80/443 closed, or (TLS=internal) the certificate is not trusted on this machine |
| `check-urls.sh`: 502 | the proxy answers but the container does not: `scripts/health-check.sh`, `docker logs <container>` |
| `docker logs tbproxy`: *could not get certificate* | Let's Encrypt cannot reach the name: public DNS record and ports 80/443 from the internet, or use `TLS=internal` |
| Login fails from a name | the name is not in that environment's settings: fix it in `tbapps.conf`, `apply --force <ENV>`, push, `./deploy-all.sh` |
| Strapi admin login fails | the seed's admin accounts have Timebars Ltd.'s passwords: reset yours ([section 5](#5-after-every-first-deploy)). After 5 failed tries Strapi waits 5 minutes |
| Strapi: `password authentication failed for user "strapi"` | `secrets.env` has another database password than the database: put back the copy from your vault |
| No offline mode / no service worker | not HTTPS, or the certificate is not trusted (TLS=internal), or `APP_OFFLINE=no` |

For help, send the output of `bash scripts/health-check.sh` and `docker logs --tail 100 <container>` —
never `secrets.env`, `.secrets.env` files, tokens or passwords.
