# Installation and Configuration of the Timebars System — Container Option

> **Rehearsed end to end** on a test server (Ubuntu 26.04, Docker 29.8, October 2026). Since then every
> stack is deployed the same way: one settings file `tbapps.conf`, the image tag in `.env`, `./deploy.sh` in each
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
| `tbpgdb` | PostgreSQL database for Strapi | `$TB/postgres` |
| `tbbe` | Strapi backend: login, licences, publishing, registration email | `$TB/tbbe` |
| `tbwwwp` | website: sales, sign-up, profile, orders | `$TB/tbwww` |
| `tbhelpapp` | Timebars Cloud (dashboards, notifications) and the AI service behind Ask AI, AI Create and the help assistant; holds your Gemini key | `$TB/tbhelp` |
| `tbrun` | the Agilebars / Timebars / Costbars app, every hostname (works offline after first load) | `$TB/tbrun` |
| `cloudflared` | *optional* — Cloudflare Tunnel for public HTTPS addresses | `$TB/cloudflared` |

**Every stack works the same way.** Each folder holds:

| File | What | Who writes it |
|---|---|---|
| `docker-compose.yml`, `.env.example`, `deploy.sh` | from this package | `00-push-to-server.sh` |
| `.env.local` | this stack's settings (`chmod 600`) — **written for you**, never edited by hand | `03-config.sh apply` |
| `.env` | one line: the image tag running now | `deploy.sh` |
| `runtime-config.json` | `tbrun` only, instead of `.env.local`: the app's addresses (no secrets) | `03-config.sh apply` |

**All your settings are in one file, `$TB/tbapps.conf`**: your addresses (typed once), the keys you paste,
and the passwords generated on the server. `03-config.sh apply` writes every `.env.local` and
`runtime-config.json` from it (section 7).

To start or update a stack: `cd $TB/<stack> && ./deploy.sh` and type the tag from `VERSION.md`.
To change a setting: edit `tbapps.conf`, then `bash $TB/scripts/03-config.sh apply` — it recreates the
containers whose settings changed. Images are never rebuilt for your server.

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
 ~/tbown  (this package, your copy)            <parent>/tbApps = $TB
   docker/   scripts/   seed/      ── 00-push-to-server.sh ──►   $TB/postgres  tbbe  tbwww  tbhelp  tbrun  cloudflared
                                               $TB/scripts/   $TB/seed/
                                               $TB/tbapps.conf   ← your settings; passwords generated ON the server
```

The stack folders must be on the server because Docker runs there and reads them locally. Secrets
are generated on the server and never leave it — not to your workstation, not into Git.

**What you need before you start**

| Item | Notes |
|---|---|
| Admin workstation on the same network | Linux, macOS, or Windows with OpenSSH; `git` or a release download of this package; `rsync` |
| Your hostnames | one per product (e.g. `pmrm.example.com`), plus the backend, the website and Timebars Cloud — section 2.1 |
| DNS and HTTPS | **your responsibility** — a Cloudflare account with your domain (section 8.1), or your own DNS, reverse proxy and certificates (section 8.2) |
| Docker Hub access | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token |
| Your keys | a Cloudflare tunnel token, a Google Gemini key, a SendGrid key; Stripe keys only if you sell licences — section 2.1 says where to get each |

On your workstation:
```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown      # or unpack a release download to ~/tbown
cd ~/tbown
```

### 2.1 The settings you will need — read this before you start

Every setting lives in one file, `tbapps.conf` (section 7.1). `03-config.sh new` writes it for you from your
domain; you then paste a few keys. This section says what each setting is, why it is needed and where to
get it, so you can collect them before the installation day.

**Part 1 — your addresses (`03-config.sh new` proposes them; hostnames only: no `https://`, no `/`)**

| Setting | Example | What it is |
|---|---|---|
| `APP_AB_HOST`, `APP_TB_HOST`, `APP_CB_HOST` | `agile.example.com`, `pmrm…`, `ppm…` | the addresses users open for Agilebars, Timebars and Costbars |
| `APP_OFFLINE` | `yes` | `yes` = those three keep working without a network after the first visit (needs HTTPS) |
| `EXTRA_APP_HOSTS` | `ab.example.com:AB tb.example.com:TB` | optional extra app addresses, without offline mode |
| `BACKEND_HOST` | `be2.example.com` | Strapi: logins, licences, publishing. Its admin page is `https://<this>/admin` |
| `WEBSITE_HOST` | `www.example.com` | the website: sales, sign-up, profile, orders |
| `CLOUD_HOST` | `cloud.example.com` | Timebars Cloud: dashboards, notifications, AI help |
| `EMAIL_FROM` | `noreply@example.com` | the sender of registration and password emails — must be a sender verified in SendGrid |

Every address needs a DNS name pointing at this server — a Cloudflare published application (section 8.1)
or a record on your own DNS and proxy (section 8.2). `apply` works out everything that depends on them: the
URLs each container uses, the list of browser addresses Strapi accepts (CORS) and the app's site list.

**Part 2 — keys you get and paste**

| Setting | Needed for | Where to get it |
|---|---|---|
| `TUNNEL_TOKEN` | public HTTPS addresses through Cloudflare (no open ports) | [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → *Networks* → *Tunnels* → **Create a tunnel** → *Cloudflared* → name it after the server → *Choose your environment*: **Docker**. The page shows `docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJh…` — copy only the long value after `--token` (it starts with `eyJ`). For an existing tunnel: *Tunnels* → the tunnel → *Configure* shows the same command. One tunnel and token per server. Leave empty if you use your own reverse proxy (section 8.2) |
| `GEMINI_API_KEY` | Ask AI, AI Create, the help assistant | [aistudio.google.com](https://aistudio.google.com) → **Get API key** → *Create API key* (in a Google Cloud project you own) → copy it (starts with `AIza`). In the Google Cloud console restrict the key to the *Generative Language API*, and add billing with a budget alert if you expect more than the free tier. Empty = AI features off |
| `SENDGRID_API_KEY` | registration confirmation and password-reset emails, sent by Strapi | [twilio.com/en-us/sendgrid](https://www.twilio.com/en-us/sendgrid) → sign up → *Settings* → *Sender Authentication*: verify your `EMAIL_FROM` address (single sender) or your whole domain → *Settings* → *API Keys* → **Create API Key**, *Restricted Access* with **Mail Send** → copy it (starts with `SG.`; shown only once). Empty = no email |
| `STRAPI_ADMIN_TOKEN` | the website (confirming Google / GitHub sign-ups) and Cloud (dashboard sources, Users & Roles) | made **after** Strapi is running: `https://<BACKEND_HOST>/admin` → *Settings* → *API Tokens* → **Create new API token**, *Full access*, *Unlimited* (section 15). Empty until then |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` | only if you sell licences on the website (checkout) | [dashboard.stripe.com](https://dashboard.stripe.com) → *Developers* → *API keys*. For a test or staging server switch to the **sandbox** first (top left) and use `sk_test_…` / `pk_test_…`; for production leave the sandbox and use `sk_live_…` / `pk_live_…`. Leave both empty if you do not sell |

**Part 4 — made on the server by `apply` (you do nothing, but know what they are)**

| Setting | What it protects | If it changes later |
|---|---|---|
| `POSTGRES_PASSWORD` | the database administrator login (admin use only) | — |
| `STRAPI_DB_NAME`, `STRAPI_DB_USER`, `STRAPI_DB_PASSWORD` | Strapi's own database and login, created on the first database start | Strapi can no longer open its database — **never change after the first start** |
| `APP_KEYS` | signs Strapi's session cookies (four values) | users are signed out once |
| `ADMIN_JWT_SECRET` | signs Strapi admin-panel logins | admins are signed out once |
| `JWT_SECRET` | signs the logins of app and website users | every user is signed out once |
| `API_TOKEN_SALT` | protects Strapi API tokens | every API token (e.g. `STRAPI_ADMIN_TOKEN`) stops working — make new ones |
| `TRANSFER_TOKEN_SALT` | protects Strapi data-transfer tokens | transfer tokens stop working |
| `WWW_NEXTAUTH_SECRET`, `CLOUD_NEXTAUTH_SECRET` | sign the website's and Cloud's session cookies | users of that site are signed out once |
| `PGADMIN_DEFAULT_PASSWORD` | the optional pgAdmin page | — |

`apply` makes each one once with a strong random value and never changes it. To make one by hand (for
example to move an existing server's value in): `openssl rand -base64 32`. When you move an installation to
a new server, bring its `tbapps.conf` along — the same part 4 keeps every login and token working.

**Coming from an older Timebars server `.env`?** These names changed or are no longer used:

| Old name | Now |
|---|---|
| `BE_URL`, `FE_URL` | `BACKEND_HOST`, `WEBSITE_HOST` (part 1, hostnames only) |
| `FULL_ACCESS_ADMIN_TOKEN` | `STRAPI_ADMIN_TOKEN` (part 2) — used by the website and Cloud, not by Strapi |
| `STRIPE_PK` | not read by Strapi; Stripe keys are the website's (`STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`) |
| `DATABASE_HOST`, `DATABASE_PORT` | fixed inside the installation (`tbpgdb`, `5432`) |
| `DATABASE_NAME`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` | `STRAPI_DB_NAME`, `STRAPI_DB_USER`, `STRAPI_DB_PASSWORD` (part 4; a restored backup is loaded into them, whatever names the old server used) |
| `API_TOKEN_SALT`, `TRANSFER_TOKEN_SALT`, `ADMIN_JWT_SECRET`, `JWT_SECRET`, `APP_KEYS` | the same names, part 4 — copy the old values in before the first `apply` to keep existing logins and tokens |

## 3. Getting into the server from your workstation

Installing on the machine you are working on? Skip this section and use `local` (section 5.1).

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

Decide where Timebars goes on the server: the **parent folder** where you keep Docker apps, given as a
**full path starting with `/`** — for example `/docker/compose`, `/srv/docker` or `/home/<you>`. The script
creates a folder **`tbApps`** inside it and puts everything there (e.g. `/docker/compose/tbApps`). Timebars
then never mixes with your other apps.

On your workstation, in your copy of the package:
```bash
cd ~/tbown && git pull                                  # latest version (skip for a release download)
bash scripts/00-push-to-server.sh myserver /docker/compose
```
Leave the folder out and the script asks for it; it remembers your answer for that server next time. If the
parent belongs to root, the script tells you the one `sudo` command to run on the server first.

It copies the stack folders, the scripts and the seed data, and sets **`TB`** to the tbApps folder in your
`~/.bashrc` on the server — every command in this guide uses `$TB` (e.g. `cd $TB/tbbe`). Run it again
whenever the package is updated: it never overwrites or deletes what belongs to the server (`tbapps.conf`,
the `.env.local` files, `runtime-config.json`, uploaded files). If the server is your workstation itself, use `local` as the
server name.

All remaining steps run **on the server**. Open a session and stay in it:
```bash
ssh myserver
echo $TB                                                # e.g. /docker/compose/tbApps
```

### 5.1 Installing on the machine you are working on (no SSH)

When the package and Docker are on the **same machine** — you install on the computer you are sitting at,
or your copy of the package is already on the server — there is nothing to connect to: no SSH server
is needed and section 3 does not apply. Use the word `local` instead of a server name:
```bash
cd ~/tbown                                              # wherever your copy of the package is
bash scripts/00-push-to-server.sh local /docker/compose
source ~/.bashrc                                        # this terminal learns $TB (new terminals have it)
echo $TB                                                # /docker/compose/tbApps
```
`local` is not a host name: `ssh local` or `ssh <this machine>` will fail (*Could not resolve hostname*,
*Connection refused*) and is not needed. Skip every `ssh myserver` / `exit` line in this guide and run
the commands in your own terminal. `echo $TB` printing nothing only means this terminal was open before
the script set it: run `source ~/.bashrc`.

## 6. Install Docker

```bash
sudo bash $TB/scripts/01-install-docker.sh
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
belong to you, in `$TB`. If a script says it cannot use Docker, log out and back in (section 6).

```bash
bash $TB/scripts/02-create-volumes.sh      # database volumes and the network tbnet
```

### 7.1 Make your settings file, `tbapps.conf`

Every setting of the installation is in **one plain-text file**. You type each address once; every other
value (the URLs each container needs, Strapi's allowed origins, the app's `runtime-config.json`) is worked
out from it.

**a. Answer a few questions** — on your workstation (in your copy of the package) or on the server:
```bash
bash scripts/03-config.sh new              # workstation: writes tbapps.conf in the package folder
bash $TB/scripts/03-config.sh new          # or on the server: writes $TB/tbapps.conf
```
It asks your domain (e.g. `example.com`), an optional letter added to every name (`s` for a staging
server: `agiles`, `be2s` …), proposes the six addresses — press Enter to accept each — and asks whether to
add the short `ab` / `tb` / `cb` addresses as optional extras. Run it again later to change the addresses: it keeps
part 2 (your keys), part 3 and part 4 (the passwords), and saves the old file next to it.

**b. Paste your keys** into part 2 of the file, in any text editor: the tunnel token (section 8.1), your
Gemini key (section 13), your SendGrid key. Leave empty what you do not use; `STRAPI_ADMIN_TOKEN` comes
later (section 15).

**c. Put it on the server** (only if you made it on the workstation) — open the file there and paste the
whole text in one go:
```bash
nano $TB/tbapps.conf                       # paste, then Ctrl+O, Enter (save), Ctrl+X (leave)
```

**d. Apply it**:
```bash
bash $TB/scripts/03-config.sh apply
```
`apply` checks the file (hostnames only, no `https://`, no address used twice, emails look like emails),
generates every password and key that is made on the server — the first time only, kept from then on —
writes them into part 4 of `tbapps.conf`, and writes each stack's `.env.local` and
`tbrun/runtime-config.json`. It lists what changed per stack and, if those containers are already
running, offers to recreate them. `bash $TB/scripts/03-config.sh check` shows the same list without
writing anything.

The file has four parts:

| Part | What | Who |
|---|---|---|
| 1. Your addresses | `APP_AB_HOST`, `APP_TB_HOST`, `APP_CB_HOST`, `APP_OFFLINE`, `EXTRA_APP_HOSTS` (e.g. `ab.example.com:AB tb.example.com:TB`), `BACKEND_HOST`, `WEBSITE_HOST`, `CLOUD_HOST`, `EMAIL_FROM` … | you (`new` fills them) |
| 2. Keys you paste | `TUNNEL_TOKEN`, `GEMINI_API_KEY`, `SENDGRID_API_KEY`, `STRAPI_ADMIN_TOKEN`, Stripe (section 2.1) | you |
| 3. Optional extras | any other setting for one stack, e.g. `TBHELP__AI_REQUIRE_LOGIN=false` | you, rarely |
| 4. Made on the server | database passwords, Strapi secrets, sign-in secrets | `apply` — never edit |

**Keep a copy of `tbapps.conf` in your password manager or secrets vault**: it holds every password of the
installation, and a restore or a move to another server starts from it. It is `chmod 600`; edit it with
`nano $TB/tbapps.conf` as your own user (no `sudo`). Typing only a file's path tries to *run* it and answers
*Permission denied* — put `nano` in front.

**A server set up before `tbapps.conf`** (settings in `.env.local` files): make the file from what is
there, keeping every password, then check that nothing would change:
```bash
bash $TB/scripts/03-config.sh import && bash $TB/scripts/03-config.sh check
```

## 8. Public addresses: DNS, HTTPS and the tunnel

Do this **now**, before starting the other stacks, so every address exists while you install: after each
stack in sections 9–14, `07-check-urls.sh` (section 16) tests it from the outside. Until a stack is up its
address answers 502 — expected.

Choose **one** of the two ways. Either way, users reach the apps only over HTTPS (required for
offline mode).

### 8.1 Cloudflare Tunnel (no open ports)

1. In Cloudflare Zero Trust → Networks → Tunnels, create a tunnel (one per server) and paste its token as
   `TUNNEL_TOKEN=` in `tbapps.conf`, then `bash $TB/scripts/03-config.sh apply`.
2. `cd $TB/cloudflared && ./deploy.sh` — it shows *Registered tunnel connection*, and the tunnel shows
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
(`cd $TB/cloudflared && docker compose down`), then put the same token in the new server's
`tbapps.conf`, `03-config.sh apply` and `./deploy.sh` in its cloudflared folder. Never run one token on two servers at once — Cloudflare would split
visitors between them.

### 8.2 Your own DNS, reverse proxy and certificates

See [`docker/proxy-example/README.md`](docker/proxy-example/README.md): which local address each
hostname points at, where your certificate and key go, and an example nginx configuration.
DNS records, certificates and their renewal are your responsibility.

## 9. Database

```bash
cd $TB/postgres && ./deploy.sh      # Enter = the tag in VERSION.md (16)
docker logs tbpgdb | grep initdb         # "created role strapi and database strapi"
```
On first start an empty database is created for Strapi, with its own login (not the superuser).

The log line `initdb: warning: enabling "trust" authentication for local connections` is the official
PostgreSQL image's default: it applies only to connections *inside* the container (used by the
backup and restore scripts through `docker exec`). Connections from other containers, such as
Strapi, need the password, and the port is reachable only from the server itself (`127.0.0.1:5433`).

## 10. Strapi backend

```bash
cd $TB/tbbe
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
bash $TB/scripts/04-restore.sh            # loads $TB/seed/seed.dump and seed-uploads.tar.gz
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
bash $TB/scripts/07-check-urls.sh       # the Strapi lines are OK now
```

## 12. Website

```bash
cd $TB/tbwww && ./deploy.sh          # Enter = the tag in VERSION.md
```
Every address and key comes from `tbapps.conf` (written to `tbwww/.env.local`) at run time. Sign-in with email and password
works against your backend. Google / GitHub / Facebook sign-in and payments stay off until you add their
keys (*Administrators Guide*). The Personal and Enterprise dashboards are on Timebars Cloud (13); old
`/dashboard` links on the website forward there.

## 13. Timebars Cloud and the AI service

Ask AI, AI Create and the help assistant run in this container, with the Cloud pages (dashboards,
notifications). It keeps your Gemini key on the server (never in the browser), and answers only users who
are logged in to your Timebars Cloud (Strapi).

1. Create a Gemini key in your own Google account (aistudio.google.com → *API keys*), restricted to the
   Generative Language API. Turn on billing and a budget alert if you expect more than the free tier.
2. Put it in `tbapps.conf` as `GEMINI_API_KEY=` (if you did not already in section 7), then
   `bash $TB/scripts/03-config.sh apply`.
3. Deploy:
```bash
cd $TB/tbhelp && ./deploy.sh
```
It checks that the AI routes answer. The AI service needs **no public address of its own**: the browser
calls the app's address and the app forwards `/ai/` to this container over `tbnet`. A site with no Strapi
(no login) adds `TBHELP__AI_REQUIRE_LOGIN=false` to `tbapps.conf` part 3, applies, and keeps the server
reachable from its own network only.

## 14. The app

One image serves every app hostname — with or without offline mode — and every customer. Its addresses are
in `tbrun/runtime-config.json`, written by `03-config.sh apply` from `tbapps.conf`:
```bash
cd $TB/tbrun && ./deploy.sh     # Enter = the tag in VERSION.md
```
Each app address in `tbapps.conf` becomes a `sites` row that maps the hostname to its product (`AB`
Agilebars, `TB` Timebars, `CB` Costbars); the three main ones work offline when `APP_OFFLINE=yes`, the
`EXTRA_APP_HOSTS` ones never. A hostname that is not listed gets no product. After a change: edit
`tbapps.conf`, apply, then reload the page twice.

In Cloudflare, every app hostname points at `http://tbrun:80` (section 8.1); an old route to
`tbrun-offline` answers 502.

## 15. The Strapi API token

The website (confirming Google / GitHub sign-ups, docs sync) and Timebars Cloud (dashboard sources,
Users & Roles) call Strapi with a server-side token.

1. Open `https://<your backend address>/admin`, sign in, then Settings → API Tokens → **Create new API token**:
   name `<server>-server`, duration **Unlimited**, type **Full access**. Save and copy it.
2. Paste it as `STRAPI_ADMIN_TOKEN=` in `tbapps.conf`, then apply and let it recreate `tbwwwp` and
   `tbhelpapp`:
```bash
nano $TB/tbapps.conf
bash $TB/scripts/03-config.sh apply
```
This is how every setting changes: edit `tbapps.conf`, apply — no new image.

## 16. Check the installation

```bash
bash $TB/scripts/06-health-check.sh      # inside the server: every container, its health and running tag
bash $TB/scripts/07-check-urls.sh        # from outside: every public address, through the tunnel or proxy
```
`06` compares each container's tag with `VERSION.md`. `07` reads your addresses from the settings files
(written from `tbapps.conf`: every app address including the extras, Strapi, the website and Cloud) and checks each page, the AI route, the offline worker, `runtime-config.json`, the dashboard
redirect and Strapi's CORS answer for every app address. A FAIL line says what to fix (a missing route,
a wrong container name, a missing CORS origin).

Then in a browser: open each app address (the product title matches the hostname), sign in, check
*Show License*, publish a dataset and open it on the dashboard, and ask the help assistant a question
(Ask AI works only when you are signed in). On an app address, DevTools →
Application → Service Workers shows `sw.js` activated; tick *Offline* and press F5 — the app still loads.

## 17. Backups

```bash
bash $TB/scripts/05-backup.sh           # try it once
crontab -e                                   # then schedule it nightly:
# 15 2 * * * /bin/bash $HOME/docker/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup holds the Strapi database, its uploads, `tbapps.conf` and the files written from it (the folder is private to your admin user). Copy `~/backups/timebars` off the server with your normal backup system, and practise a
restore.

Users' own project data lives in their browsers: their backup files and synced spreadsheets go into
your document management system (see the *Data Synchronization, Backup, Recovery and Retention* guide).

## 18. Updates and rollback

| What | How |
|---|---|
| This package | workstation: `git pull` (or new release), then `bash scripts/00-push-to-server.sh myserver` |
| Any container | server: `cd $TB/<stack> && ./deploy.sh` and type the new tag from `VERSION.md`; back up first for `tbbe` |
| Roll back | the same, with the previous tag (`deploy.sh` shows the one running now) |
| A setting (address, key) | edit `tbapps.conf`, then `bash $TB/scripts/03-config.sh apply` (it recreates what changed) |
| PostgreSQL major version | backup → new empty volume → `./deploy.sh` with the new major tag → restore (`deploy.sh` refuses a major change on a database with data) |
| Ubuntu, firewall, SSH | your administrator, under your policies |

**From an earlier copy of this package** (folders `tbrunoffline` and `tbwwwp`, settings in `.env`, networks
`postgres_tbpg_net` and `tbhelp`): run `00-push-to-server.sh`, then on the server, for each old folder,
`docker compose down`; make `tbapps.conf` with `03-config.sh new`, and copy the database passwords and
Strapi secrets from the old `postgres/.env` and `tbbe/.env` into its part 4 (`POSTGRES_PASSWORD`,
`STRAPI_DB_PASSWORD`, `APP_KEYS`, `API_TOKEN_SALT`, `ADMIN_JWT_SECRET`, `TRANSFER_TOKEN_SALT`, `JWT_SECRET`)
before the first `apply`; then `bash $TB/scripts/02-create-volumes.sh` and `./deploy.sh` in each stack,
database first. Delete the old folders and networks (`docker network rm postgres_tbpg_net tbhelp`) once
everything is green. Change the tunnel routes to `http://tbrun:80` for the app hostnames.

**From the first `tbApps` layout** (settings typed into each `.env.local`): `bash $TB/scripts/03-config.sh
import`, then `check` — it should show no changes. From then on edit `tbapps.conf` only.

## 19. Troubleshooting

| Symptom | Fix |
|---|---|
| `kex_exchange_identification: Connection reset by peer` | your workstation offered too many keys; use `IdentitiesOnly yes` (section 3) and wait a few minutes |
| `00-push-to-server.sh`: *rsync is missing* | install `rsync` on the workstation or ask the administrator to install it on the server (section 4.7) |
| `apt`: *Temporary failure resolving* | the server has no DNS — your administrator sets gateway and DNS servers |
| `permission denied ... docker.sock` | log out and back in after section 6 |
| Docker install says *Cannot reach download.docker.com* | the server has no internet access to Docker (proxy, firewall); fix it and run the script again |
| `tbpgdb` keeps restarting; log: *database files are incompatible with server … initialized by PostgreSQL version 14* | the volume `postgres_db` holds a database from an earlier install. Not needed: `cd $TB/postgres && docker compose down; docker volume rm postgres_db; bash $TB/scripts/02-create-volumes.sh; ./deploy.sh`. Needed: back it up with the old version first, then restore it into the new one (`04-restore.sh`) |
| Strapi cannot reach the database | the database was made with other passwords than `tbapps.conf` part 4 holds — restore the old `tbapps.conf` from your vault or backup, apply |
| AI answers *502* | `tbhelpapp` is not running, or it or `tbrun` is not on network `tbnet` — `docker network inspect tbnet` lists both; `./deploy.sh` in `tbhelp`, then in `tbrun` |
| AI answers *503* "Could not check your login right now" | `tbhelpapp` cannot reach Strapi — `tbbe` is down, or a `TBHELP__STRAPI_URL` line in `tbapps.conf` overrides the right value (`http://tbbe:1337/api`); test: `docker exec tbhelpapp wget -S -O- http://tbbe:1337/api/users/me` answers 401/403 when healthy |
| AI answers *401* | the user is not signed in, or the login expired |
| AI answers an error naming `GEMINI_API_KEY` | add `GEMINI_API_KEY=` to `tbapps.conf`, apply |
| App address shows the wrong product or none | add the hostname to `tbapps.conf` (part 1), apply, then reload twice |
| Login fails from a new address | the address is not in `tbapps.conf` (Strapi only accepts addresses listed there, plus `EXTRA_CORS_ORIGINS`); add it, apply |
| No service worker | not HTTPS, the address lacks `"offline": true`, or `runtime-config.json` is not served |
| `07-check-urls.sh`: 530 for an address | no published application for that hostname on the running tunnel — add it (section 8.1) |
| `07-check-urls.sh`: 502 for an address | the route names the wrong container or port, or the container is down (`06-health-check.sh`) |
| `docker logs cloudflared`: *lookup tbwwwp on 127.0.0.11:53: server misbehaving* (browser: Cloudflare 502) | that container is not running, or not on `tbnet` — `./deploy.sh` in its stack; the tunnel route needs no change |
| Published application with `localhost:8687` does not work | inside the cloudflared container `localhost` is cloudflared itself — use the container name (`tbrun:80`, `tbbe:1337`, `tbwwwp:3001`, `tbhelpapp:3010`) |
| `bash: $TB/tbapps.conf: Permission denied` | you typed the file's path as a command; open it with `nano $TB/tbapps.conf` (section 7.1) |
| An editor cannot save `tbapps.conf` | it was created with `sudo`: `sudo chown $USER: $TB/tbapps.conf $TB/*/.env.local` once, then no `sudo` again |
| `deploy.sh`: *Not set: ...* | add those values to `tbapps.conf`, then `03-config.sh apply` |
| `docker compose`: *env file .env.local not found* | `bash $TB/scripts/03-config.sh apply` (section 7.1) |
| Strapi admin login fails; `docker logs tbbe` shows *originList.split is not a function* | the backend's own address was not an allowed origin. Fixed in `03-config.sh apply` (it now lists `BACKEND_HOST` too) and in tbbe images after 2026.10.09: run `bash $TB/scripts/03-config.sh apply` and recreate tbbe |
| Strapi admin login fails with the right page shown | wrong email or password for the account in the restored data — list the admin accounts: `docker exec tbpgdb psql -U strapi -d strapi -Atc "select email, is_active, blocked from admin_users"`, and reset a password with `docker exec -it tbbe strapi admin:reset-user-password` (it asks for the email and the new password). After 5 failed tries Strapi refuses every login for that email for 5 minutes — wait before trying again |
| `03-config.sh apply`: *Stopped: the database already exists* | `tbapps.conf` would change the database passwords — put the old part 4 back (from your vault, or `03-config.sh import` into another file) |

For help, send the output of `bash $TB/scripts/06-health-check.sh` and
`docker logs --tail 100 <container>` — never send `tbapps.conf`, `.env.local` files, tokens or passwords.
