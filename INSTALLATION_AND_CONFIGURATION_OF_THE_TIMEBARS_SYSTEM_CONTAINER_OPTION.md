# Installation and Configuration of the Timebars System — Container Option

> **Rehearsed end to end** on a test server (Ubuntu 26.04, Docker 29.8, October 2026). Since then every
> stack is deployed the same way: settings in `.env.local`, the image tag in `.env`, `./deploy.sh` in each
> folder, one Docker network `tbnet`. The images are generic — nothing about your server is built into them.

## Contents

1. [What you are installing](#1-what-you-are-installing)
2. [How the installation works](#2-how-the-installation-works)
3. [Getting into the server from your workstation](#3-getting-into-the-server-from-your-workstation)
4. [Server requirements (your administrator)](#4-server-requirements-your-administrator)
5. [Send the package to the server](#5-send-the-package-to-the-server)
6. [Install Docker](#6-install-docker)
7. [Volumes, network and settings](#7-volumes-network-and-settings)
8. [Public addresses: DNS, HTTPS and the tunnel](#8-public-addresses-dns-https-and-the-tunnel)
9. [Database](#9-database)
10. [Strapi backend](#10-strapi-backend)
11. [Load the seed data or a backup](#11-load-the-seed-data-or-a-backup)
12. [Website](#12-website)
13. [Timebars Cloud and the AI service](#13-timebars-cloud-and-the-ai-service)
14. [The app](#14-the-app)
15. [The Strapi API token](#15-the-strapi-api-token)
16. [Check the installation](#16-check-the-installation)
17. [Backups](#17-backups)
18. [Updates and rollback](#18-updates-and-rollback)
19. [Troubleshooting](#19-troubleshooting)

---

## 1. What you are installing

| Container | What it does | Folder on the server |
|---|---|---|
| `tbpgdb` | PostgreSQL database for Strapi | `~/docker/postgres` |
| `tbbe` | Strapi backend: login, licences, publishing, registration email | `~/docker/tbbe` |
| `tbwwwp` | website: sales, sign-up, profile, orders | `~/docker/tbwww` |
| `tbhelpapp` | Timebars Cloud (dashboards, notifications) and the AI service behind Ask AI, AI Create and the help assistant; holds your Gemini key | `~/docker/tbhelp` |
| `tbrun` | the Agilebars / Timebars / Costbars app, every hostname (works offline after first load) | `~/docker/tbrun` |
| `cloudflared` | *optional* — Cloudflare Tunnel for public HTTPS addresses | `~/docker/cloudflared` |

**Every stack works the same way.** Each folder holds:

| File | What | Who writes it |
|---|---|---|
| `docker-compose.yml`, `.env.example`, `deploy.sh` | from this package | `00-push-to-server.sh` |
| `.env.local` | your settings: passwords, keys and this server's addresses (`chmod 600`) | `03-generate-secrets.sh`, then you |
| `.env` | one line: the image tag running now | `deploy.sh` |
| `runtime-config.json` | `tbrun` only, instead of `.env.local`: the app's addresses (no secrets) | you |

To start or update a stack: `cd ~/docker/<stack> && ./deploy.sh` and type the tag from `VERSION.md`.
To change a setting: edit `.env.local` (or `runtime-config.json`), then `docker compose up -d --force-recreate`.
Images are never rebuilt for your server.

All containers share one Docker network, **`tbnet`**, and reach each other by name. Their ports are bound to
the server itself (`127.0.0.1`) — nothing is reachable from the network until you publish it through the
tunnel or your own reverse proxy (section 8).

Project data lives in each user's browser; the server holds accounts, licences and published data.

## 2. How the installation works

| Who | Where | Does what |
|---|---|---|
| **Your server administrator** | the server | provides a server that meets section 4, under your organisation's own policies (patching, firewall, SSH, hardening) |
| **You (installer)** | your admin workstation | keeps this package (clone or release download), sends it to the server with one command (section 5), and runs every other step from an SSH session |
| **The scripts in this package** | the server | install Docker and the Timebars stack, generate secrets, back up and restore |

```text
 workstation                                   server
 ~/tbown  (this package, your copy)            ~/docker/postgres  tbbe  tbwww  tbhelp  tbrun  cloudflared
   docker/   scripts/   seed/      ── 00-push-to-server.sh ──►   ~/docker/scripts/   ~/docker/seed/
                                               ~/docker/*/.env.local   ← created ON the server, never copied back
```

The stack folders must be on the server because Docker runs there and reads them locally. Secrets
are generated on the server and never leave it — not to your workstation, not into Git.

**What you need before you start**

| Item | Notes |
|---|---|
| Admin workstation on the same network | Linux, macOS, or Windows with OpenSSH; `git` or a release download of this package; `rsync` |
| Your hostnames | one per product you use (e.g. `pmrm.example.com`), plus the backend (`be2.example.com`) and website (`www.example.com`) |
| DNS and HTTPS | **your responsibility** — a Cloudflare account with your domain (section 8.1), or your own DNS, reverse proxy and certificates (section 8.2) |
| Docker Hub access | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token |
| Optional services | SendGrid key (registration email), Pushover / Twilio (notifications) — see the *Administrators Guide* |

On your workstation:
```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown      # or unpack a release download to ~/tbown
cd ~/tbown
```

## 3. Getting into the server from your workstation

Two files on the workstation are involved, and they do different jobs:

| File | What it does | Used by |
|---|---|---|
| `/etc/hosts` | gives the server a **name** (→ its IP) | every program: ping, browser, curl, ssh |
| `~/.ssh/config` | an **SSH shortcut**: address, user, which key to use | ssh, scp, rsync only |

SSH does not need `/etc/hosts`; add both so the name also works for ping, curl and the browser.
If your organisation has DNS for the server, a DNS record replaces step 1. The examples call the
server `myserver`.

```bash
# 1. a name for the server (its real IP and name)
grep -q ' myserver$' /etc/hosts || echo "192.168.1.205  myserver" | sudo tee -a /etc/hosts
ping -c2 myserver

# 2. SSH shortcut
cat >> ~/.ssh/config <<'CFG'

Host myserver
    HostName myserver
    User admin
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
CFG
chmod 600 ~/.ssh/config

# 3. your key on the server (asks the server password once - before password logins are turned off)
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "$USER@$(hostname)"
ssh-copy-id -i ~/.ssh/id_ed25519.pub myserver
ssh myserver hostname        # prints the server name, no password
```
`IdentitiesOnly yes` matters: without it SSH offers every key you have, and newer OpenSSH servers
temporarily block an address after several failed attempts (*Connection reset by peer*).

## 4. Server requirements (your administrator)

The server is yours: your administrator builds, patches and secures it under your organisation's
policies. The Timebars stack needs the **end state** below; how it is reached is your choice. Each
row has a check you can run from your workstation.

| # | The stack needs | Check (from your workstation) |
|---|---|---|
| 4.1 | Ubuntu 24.04 or 26.04 LTS, 64-bit, kept patched (security updates applied) | `ssh myserver lsb_release -ds` |
| 4.2 | At least 2 CPU cores, 4 GB RAM, 100 GB disk; swap on a 4 GB server | `ssh myserver 'nproc; free -h; df -h /'` |
| 4.3 | Correct time, synchronised (NTP) | `ssh myserver timedatectl \| grep synchronized` → `yes` |
| 4.4 | A fixed address, and outbound internet to Docker Hub (and Cloudflare, if used) | `ssh myserver curl -sI https://registry-1.docker.io/v2/ \| head -1` → `401` (reachable) |
| 4.5 | An admin user with `sudo`, key-only SSH from your admin network | `ssh -o PubkeyAuthentication=no myserver` is refused |
| 4.6 | Host firewall: inbound SSH from the admin network only (plus 80/443 only if you run your own proxy on this server, section 8.2) | `ssh -t myserver sudo ufw status` (or your firewall's equivalent) |
| 4.7 | Installed: `curl`, `ca-certificates`, `rsync`, `tar`, `openssl`, `python3` | `ssh myserver 'command -v curl rsync tar openssl python3'` |
| 4.8 | Docker is **not** pre-installed by another method (snap, distribution packages) — section 6 installs it | `ssh myserver 'command -v docker'` prints nothing |

> **Firewall note for your administrator.** The compose files publish container ports on
> `127.0.0.1` only. Keep it that way: Docker writes its own firewall rules, and a port published on
> all addresses is reachable from the network **even when the host firewall denies it**. A network
> firewall in front of the server needs no inbound rule except SSH (and 80/443 for your own proxy).

## 5. Send the package to the server

On your workstation, in your copy of the package:
```bash
cd ~/tbown && git pull                          # latest version (skip for a release download)
bash scripts/00-push-to-server.sh myserver
```
This copies the stack folders, the scripts and the seed data to `~/docker` on the server. Run it again
whenever the package is updated: it never overwrites or deletes what belongs to the server (`.env`
files, `runtime-config.json`, uploaded files).

All remaining steps run **on the server**. Open a session and stay in it:
```bash
ssh myserver
```

## 6. Install Docker

```bash
sudo bash ~/docker/scripts/01-install-docker.sh
exit                                            # log out and back in, so docker works without sudo
```
```bash
ssh myserver
id -nG                                          # must list "docker" - if not, log out and in again
docker version && docker compose version        # Client and Server versions both shown
docker login -u <your Docker Hub user>          # paste your read-only access token
```
`docker login` warns that the credentials are stored unencrypted in `~/.docker/config.json`. That is
expected on a server: use a **read-only** access token (never your password) and keep the file
private (`stat -c %a ~/.docker/config.json` → `600`). Your policy may require a credential helper
instead.
The script installs `curl` and `ca-certificates` (as Docker's own instructions do), then Docker
Engine and the Compose plugin from Docker's own repository — Ubuntu's packages only if Docker has none yet for
your release; the last line says which (`from: docker packages`). It turns on log rotation for every
container and adds your user to the `docker` group. If Ubuntu's `docker.io` is already installed and
no containers exist yet, it is replaced by Docker's packages. Your administrator may prefer to install Docker under your own standards —
the stack needs Docker Engine 24+ with the Compose plugin (`docker compose`).

## 7. Volumes, network and settings

From here on, run every script **without `sudo`**, as your admin user — the files they create must
belong to you, in `~/docker`. If a script says it cannot use Docker, log out and back in (section 6).

```bash
bash ~/docker/scripts/02-create-volumes.sh      # database volumes and the network tbnet
bash ~/docker/scripts/03-generate-secrets.sh    # every .env.local, with new random passwords and keys
```
`03-generate-secrets.sh` creates each stack's `.env.local` from its `.env.example` (`chmod 600`, never
overwriting an existing one) and `tbrun/runtime-config.json` from its example. It generates every password
and key that is made on the server, and lists the values still `CHANGE_ME` — those are yours:

| File (on the server) | Set |
|---|---|
| `~/docker/tbbe/.env.local` | `PUBLIC_URL` (your backend address), `CORS_ORIGINS` (your app, website and Cloud addresses); `SENDGRID_API_KEY` and `EMAIL_FROM` if you use email |
| `~/docker/tbwww/.env.local` | `NEXTAUTH_URL` (your website address), `CLOUD_API_URL`, `CLOUD_URL`, `RUN_URL_AB` / `TB` / `CB`; Stripe and `STRAPI_ADMIN_TOKEN` when you use them |
| `~/docker/tbhelp/.env.local` | `GEMINI_API_KEY` (13), `NEXTAUTH_URL` (your Cloud address), `CLOUD_API_URL`, `CLOUD_WWW_URL`, `RUN_URL_*` |
| `~/docker/tbrun/runtime-config.json` | your backend, website and Cloud addresses, one row per app hostname (14) |
| `~/docker/cloudflared/.env.local` | `TUNNEL_TOKEN` (section 8.1) |

```bash
nano ~/docker/tbbe/.env.local
```
Each file's comments say what goes where. `deploy.sh` refuses to start a stack while a value it needs is
still `CHANGE_ME`. Store a copy of the `.env.local` files in your password manager or secrets vault — a
restore needs them.

## 8. Public addresses: DNS, HTTPS and the tunnel

Do this **now**, before starting the other stacks, so every address exists while you install: after each
stack in sections 9–14, `07-check-urls.sh` (section 16) tests it from the outside. Until a stack is up its
address answers 502 — expected.

Choose **one** of the two ways. Either way, users reach the apps only over HTTPS (required for
offline mode).

### 8.1 Cloudflare Tunnel (no open ports)

1. In Cloudflare Zero Trust → Networks → Tunnels, create a tunnel (one per server) and paste its token into
   `~/docker/cloudflared/.env.local` (`TUNNEL_TOKEN=...`).
2. `cd ~/docker/cloudflared && ./deploy.sh` — it shows *Registered tunnel connection*, and the tunnel shows
   *Healthy* in the dashboard.
3. Add one *published application* per hostname, service type **HTTP**, pointing at the **container
   name** — not `localhost` (inside cloudflared that is cloudflared itself) and not an IP address (the
   ports are bound to `127.0.0.1`). The same routes work on any server running these stacks:

| Hostname (example) | Service |
|---|---|
| `agile.example.com`, `pmrm.example.com`, `ppm.example.com` (every app hostname) | `http://tbrun:80` |
| `be2.example.com` | `http://tbbe:1337` |
| `www.example.com` | `http://tbwwwp:3001` |
| `cloud.example.com` (Timebars Cloud: dashboards, notifications, help) | `http://tbhelpapp:3010` |
| *optional:* `help.example.com`, `dashboard.example.com`, `pubsets.example.com` | `http://tbhelpapp:3010` (each forwards to its page on `cloud.example.com`) |

Keep *Rocket Loader* off and do not add *Cache Everything* rules for these hostnames.

**Moving to another server** keeps every route: stop cloudflared on the old server
(`cd ~/docker/cloudflared && docker compose down`), then put the same token in the new server's
`.env.local` and `./deploy.sh`. Never run one token on two servers at once — Cloudflare would split
visitors between them.

### 8.2 Your own DNS, reverse proxy and certificates

See [`docker/proxy-example/README.md`](docker/proxy-example/README.md): which local address each
hostname points at, where your certificate and key go, and an example nginx configuration.
DNS records, certificates and their renewal are your responsibility.

## 9. Database

```bash
cd ~/docker/postgres && ./deploy.sh      # Enter = the tag in VERSION.md (16)
docker logs tbpgdb | grep initdb         # "created role strapi and database strapi"
```
On first start an empty database is created for Strapi, with its own login (not the superuser).

The log line `initdb: warning: enabling "trust" authentication for local connections` is the official
PostgreSQL image's default: it applies only to connections *inside* the container (used by the
backup and restore scripts through `docker exec`). Connections from other containers, such as
Strapi, need the password, and the port is reachable only from the server itself (`127.0.0.1:5433`).

## 10. Strapi backend

```bash
cd ~/docker/tbbe
sudo chown -R 1000:1000 public/uploads
./deploy.sh                               # waits for Strapi to start (a minute or two); /_health answers 204
```
Create the first administrator at `https://<your backend address>/admin` once the public address
works (section 8), or now through an SSH tunnel from your workstation:
`ssh -N -L 1337:localhost:1337 myserver`, then open `http://localhost:1337/admin`.

Expected messages in the log on a first start:

| Message | Meaning |
|---|---|
| `API key does not start with "SG."` | `SENDGRID_API_KEY` is empty — Strapi runs, but sends no email |
| administration panel at `http://0.0.0.0:1337/admin` | the address Strapi listens on inside the container; use your public address or the SSH tunnel |

**Next, load the seed data (section 11)** so the website has its content (products, help articles, FAQ).

## 11. Load the seed data or a backup

```bash
bash ~/docker/scripts/04-restore.sh            # loads ~/docker/seed/seed.dump and seed-uploads.tar.gz
```
The same script restores your own backups (section 17). It replaces the Strapi database, and ends
by listing the tables that hold rows.

After the seed is loaded:
- Strapi admin (`https://<backend>/admin`): sign in with the administrator account supplied by
  Timebars Ltd. with this package, and change its password.
- API tokens stored in the seed were made under Timebars Ltd.'s secrets and do not work on your
  server — section 15 makes the one the website and Cloud need.
- In the app, sign in with a demo account: *Show License* shows the product and its limits.

Check that Strapi reads the restored data:
```bash
docker exec tbpgdb psql -U strapi -d strapi -Atc "select 'users', count(*) from up_users union all select 'products', count(*) from products"
bash ~/docker/scripts/07-check-urls.sh       # the Strapi lines are OK now
```

## 12. Website

```bash
cd ~/docker/tbwww && ./deploy.sh          # Enter = the tag in VERSION.md
```
Every address and key comes from `~/docker/tbwww/.env.local` at run time. Sign-in with email and password
works against your backend. Google / GitHub / Facebook sign-in and payments stay off until you add their
keys (*Administrators Guide*). The Personal and Enterprise dashboards are on Timebars Cloud (13); old
`/dashboard` links on the website forward there.

## 13. Timebars Cloud and the AI service

Ask AI, AI Create and the help assistant run in this container, with the Cloud pages (dashboards,
notifications). It keeps your Gemini key on the server (never in the browser), and answers only users who
are logged in to your Timebars Cloud (Strapi).

1. Create a Gemini key in your own Google account (aistudio.google.com → *API keys*), restricted to the
   Generative Language API. Turn on billing and a budget alert if you expect more than the free tier.
2. Put it, and your Cloud address, in the settings file (`chmod 600`, never copied back):
```bash
nano ~/docker/tbhelp/.env.local      # GEMINI_API_KEY, NEXTAUTH_URL; STRAPI_URL is already http://tbbe:1337/api
```
3. Deploy:
```bash
cd ~/docker/tbhelp && ./deploy.sh
```
It checks that the AI routes answer. The AI service needs **no public address of its own**: the browser
calls the app's address and the app forwards `/ai/` to this container over `tbnet`. A site with no Strapi
(no login) sets `AI_REQUIRE_LOGIN=false` in `.env.local` and keeps the server reachable from its own
network only.

## 14. The app

One image serves every app hostname — with or without offline mode — and every customer; your addresses go in `runtime-config.json`:
```bash
cd ~/docker/tbrun
nano runtime-config.json        # your backend, website and Cloud, one row per app hostname
./deploy.sh                     # Enter = the tag in VERSION.md
```
Each `sites` row maps a hostname to a product: `AB` Agilebars, `TB` Timebars, `CB` Costbars;
`"offline": true` lets that address work offline. A hostname that is not listed gets no product.
`aiBaseUrl` stays `/ai` (the app's own address, forwarded to `tbhelpapp`); change it only if you host the AI
service somewhere else. After editing the file later: `docker compose up -d --force-recreate`, then reload
the page twice.

In Cloudflare, every app hostname points at `http://tbrun:80` (section 8.1); an old route to
`tbrun-offline` answers 502.

## 15. The Strapi API token

The website (confirming Google / GitHub sign-ups, docs sync) and Timebars Cloud (dashboard sources,
Users & Roles) call Strapi with a server-side token.

1. Open `https://<your backend address>/admin`, sign in, then Settings → API Tokens → **Create new API token**:
   name `<server>-server`, duration **Unlimited**, type **Full access**. Save and copy it.
2. On the server — paste at the prompt; it is not shown or kept in the shell history:
```bash
read -rsp 'Token: ' T; echo; cd ~/docker && sed -i "s#^STRAPI_ADMIN_TOKEN=.*#STRAPI_ADMIN_TOKEN=$T#" tbwww/.env.local tbhelp/.env.local; unset T
(cd tbwww && docker compose up -d --force-recreate) && (cd tbhelp && docker compose up -d --force-recreate)
```
This is how every setting changes: edit `.env.local`, recreate the container — no new image.

## 16. Check the installation

```bash
bash ~/docker/scripts/06-health-check.sh      # inside the server: every container, its health and running tag
bash ~/docker/scripts/07-check-urls.sh        # from outside: every public address, through the tunnel or proxy
```
`06` compares each container's tag with `VERSION.md`. `07` reads your addresses from the settings files
(`PUBLIC_URL`, both `NEXTAUTH_URL`s, the `sites` rows in `runtime-config.json`; add other app hostnames as
arguments) and checks each page, the AI route, the offline worker, `runtime-config.json`, the dashboard
redirect and Strapi's CORS answer for every app address. A FAIL line says what to fix (a missing route,
a wrong container name, a missing CORS origin).

Then in a browser: open each app address (the product title matches the hostname), sign in, check
*Show License*, publish a dataset and open it on the dashboard, and ask the help assistant a question
(Ask AI works only when you are signed in). On an app address, DevTools →
Application → Service Workers shows `sw.js` activated; tick *Offline* and press F5 — the app still loads.

## 17. Backups

```bash
bash ~/docker/scripts/05-backup.sh           # try it once
crontab -e                                   # then schedule it nightly:
# 15 2 * * * /bin/bash $HOME/docker/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup holds the Strapi database, its uploads and every stack's `.env.local`, `.env` and
`runtime-config.json` (the folder is private to your admin user). Copy `~/backups/timebars` off the server with your normal backup system, and practise a
restore.

Users' own project data lives in their browsers: their backup files and synced spreadsheets go into
your document management system (see the *Data Synchronization, Backup, Recovery and Retention* guide).

## 18. Updates and rollback

| What | How |
|---|---|
| This package | workstation: `git pull` (or new release), then `bash scripts/00-push-to-server.sh myserver` |
| Any container | server: `cd ~/docker/<stack> && ./deploy.sh` and type the new tag from `VERSION.md`; back up first for `tbbe` |
| Roll back | the same, with the previous tag (`deploy.sh` shows the one running now) |
| A setting (address, key) | edit `.env.local` (or `tbrun/runtime-config.json`), then `docker compose up -d --force-recreate` in that folder |
| PostgreSQL major version | backup → new empty volume → `./deploy.sh` with the new major tag → restore (`deploy.sh` refuses a major change on a database with data) |
| Ubuntu, firewall, SSH | your administrator, under your policies |

**From an earlier copy of this package** (folders `tbrunoffline` and `tbwwwp`, settings in `.env`, networks
`postgres_tbpg_net` and `tbhelp`): run `00-push-to-server.sh`, then on the server, for each old folder,
`docker compose down`; move each stack's settings into `.env.local` (`mv .env .env.local`, then compare with
the new `.env.example`; for tbwww start from the new example — its variable names changed); copy
`tbrunoffline/runtime-config.json` to `tbrun/`; then `bash ~/docker/scripts/02-create-volumes.sh` and
`./deploy.sh` in each stack, database first. Delete the old folders and networks
(`docker network rm postgres_tbpg_net tbhelp`) once everything is green. Change the tunnel routes to
`http://tbrun:80` for the app hostnames.

## 19. Troubleshooting

| Symptom | Fix |
|---|---|
| `kex_exchange_identification: Connection reset by peer` | your workstation offered too many keys; use `IdentitiesOnly yes` (section 3) and wait a few minutes |
| `00-push-to-server.sh`: *rsync is missing* | install `rsync` on the workstation or ask the administrator to install it on the server (section 4.7) |
| `apt`: *Temporary failure resolving* | the server has no DNS — your administrator sets gateway and DNS servers |
| `permission denied ... docker.sock` | log out and back in after section 6 |
| Docker install says *Cannot reach download.docker.com* | the server has no internet access to Docker (proxy, firewall); fix it and run the script again |
| Strapi cannot reach the database | `DATABASE_*` in `tbbe/.env.local` must match `STRAPI_DB_*` in `postgres/.env.local` |
| AI answers *502* | `tbhelpapp` is not running, or it or `tbrun` is not on network `tbnet` — `docker network inspect tbnet` lists both; `./deploy.sh` in `tbhelp`, then in `tbrun` |
| AI answers *503* "Could not check your login right now" | `tbhelpapp` cannot reach Strapi — `STRAPI_URL` in `tbhelp/.env.local` is wrong (it should be `http://tbbe:1337/api`) or `tbbe` is down; test: `docker exec tbhelpapp wget -S -O- http://tbbe:1337/api/users/me` answers 401/403 when healthy |
| AI answers *401* | the user is not signed in, the login expired, or `STRAPI_URL` in `tbhelp/.env.local` is wrong |
| AI answers an error naming `GEMINI_API_KEY` | the key is missing in `tbhelp/.env.local`; add it and `docker compose up -d --force-recreate` |
| App address shows the wrong product or none | add the hostname to `runtime-config.json`, `docker compose up -d --force-recreate` in `tbrun`, then reload twice |
| Login fails from a new address | the address is missing from `CORS_ORIGINS` in `tbbe/.env.local`; add it and `docker compose up -d --force-recreate` |
| No service worker | not HTTPS, the address lacks `"offline": true`, or `runtime-config.json` is not served |
| `07-check-urls.sh`: 530 for an address | no published application for that hostname on the running tunnel — add it (section 8.1) |
| `07-check-urls.sh`: 502 for an address | the route names the wrong container or port, or the container is down (`06-health-check.sh`) |
| `docker logs cloudflared`: *lookup tbwwwp on 127.0.0.11:53: server misbehaving* (browser: Cloudflare 502) | that container is not running, or not on `tbnet` — `./deploy.sh` in its stack; the tunnel route needs no change |
| Published application with `localhost:8687` does not work | inside the cloudflared container `localhost` is cloudflared itself — use the container name (`tbrun:80`, `tbbe:1337`, `tbwwwp:3001`, `tbhelpapp:3010`) |
| `deploy.sh`: *Not set in .env.local: ...* | fill in those values (the file's comments say what goes there) and run it again |
| `docker compose`: *env file .env.local not found* | run `03-generate-secrets.sh`, or `cp .env.example .env.local` and fill it in |

For help, send the output of `bash ~/docker/scripts/06-health-check.sh` and
`docker logs --tail 100 <container>` — never send `.env.local` files, tokens or passwords.
