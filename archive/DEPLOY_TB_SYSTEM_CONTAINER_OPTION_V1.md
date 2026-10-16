# Installation and Configuration of the Timebars System — Docker Container Option

> Rehearsed end to end on a test server (Ubuntu 26.04, Docker 29.8, October 2026). Since then every container (stack) is deployed the same way: one settings file `tbapps.conf`, the docker hub image tag in `.env`, `./deploy.sh` in each folder, one Docker network `tbnet`. The images are generic — nothing about your server is built into them.

## Contents

- [Installation and Configuration of the Timebars System — Docker Container Option](#installation-and-configuration-of-the-timebars-system--docker-container-option)
  - [Contents](#contents)
  - [1. What you are installing](#1-what-you-are-installing)
  - [2. How the installation works](#2-how-the-installation-works)
    - [2.1 The settings you will need — read this before you start](#21-the-settings-you-will-need--read-this-before-you-start)
  - [3. Getting into the server from your workstation](#3-getting-into-the-server-from-your-workstation)
  - [4. Server requirements (your administrator)](#4-server-requirements-your-administrator)
    - [4.9 A new cloud server](#49-a-new-cloud-server)
  - [5. Send the package to the server](#5-send-the-package-to-the-server)
    - [5.1 Installing on the machine you are working on (no SSH)](#51-installing-on-the-machine-you-are-working-on-no-ssh)
  - [6. Install Docker](#6-install-docker)
  - [7. Volumes, network and settings](#7-volumes-network-and-settings)
    - [7.1 Make your settings file, `tbapps.conf`](#71-make-your-settings-file-tbappsconf)
  - [8. Public addresses: DNS, HTTPS, the tunnel or the proxy](#8-public-addresses-dns-https-the-tunnel-or-the-proxy)
    - [8.1 Cloudflare Tunnel (no open ports)](#81-cloudflare-tunnel-no-open-ports)
    - [8.2 Your own DNS, reverse proxy and certificates](#82-your-own-dns-reverse-proxy-and-certificates)
    - [8.3 The proxy on this server (Caddy, Let's Encrypt)](#83-the-proxy-on-this-server-caddy-lets-encrypt)
  - [9. Deploy Postgres and Database Container](#9-deploy-postgres-and-database-container)
  - [10. Deploy Strapi backend container](#10-deploy-strapi-backend-container)
  - [11. Load the seed data or a backup](#11-load-the-seed-data-or-a-backup)
  - [12. Website](#12-website)
  - [13. Timebars Cloud and the AI service](#13-timebars-cloud-and-the-ai-service)
  - [14. The app](#14-the-app)
  - [15. The Strapi API token](#15-the-strapi-api-token)
  - [16. Check the installation](#16-check-the-installation)
  - [17. Backups](#17-backups)
  - [18. Updates and rollback](#18-updates-and-rollback)
  - [19. Troubleshooting](#19-troubleshooting)
- [Appendices](#appendices)
  - [Appendix A. A domain and a server: Rebel.ca and DigitalOcean](#appendix-a-a-domain-and-a-server-rebelca-and-digitalocean)
    - [A.1 DigitalOcean: the server first (you need its IP for the DNS records)](#a1-digitalocean-the-server-first-you-need-its-ip-for-the-dns-records)
    - [A.2 Rebel.ca: the domain and its DNS records](#a2-rebelca-the-domain-and-its-dns-records)
    - [A.3 Checklist of DNS records](#a3-checklist-of-dns-records)
  - [Appendix B. A new server with the proxy, start to finish](#appendix-b-a-new-server-with-the-proxy-start-to-finish)
    - [B.1 Prepare the server (as root, once)](#b1-prepare-the-server-as-root-once)
    - [B.2 The installation](#b2-the-installation)
    - [B.3 Looking after it](#b3-looking-after-it)
  - [Appendix C. Growing: bigger and more servers](#appendix-c-growing-bigger-and-more-servers)
  - [Appendix D. Container platforms that scale by themselves](#appendix-d-container-platforms-that-scale-by-themselves)

Appendices (optional)

- [A. A domain and a server: Rebel.ca and DigitalOcean](#appendix-a-a-domain-and-a-server-rebelca-and-digitalocean)
- [B. A new server with the proxy, start to finish](#appendix-b-a-new-server-with-the-proxy-start-to-finish)
- [C. Growing: bigger and more servers](#appendix-c-growing-bigger-and-more-servers)
- [D. Container platforms that scale by themselves](#appendix-d-container-platforms-that-scale-by-themselves)

---

## 1. What you are installing

These instructions are for a single server installation, all containers run on the same box. It would be up to the customer to move containers around and networking changes to suit.

| Container Name | What it does | Folder on the server |
|---|---|---|
| `tbpgdb` | PostgreSQL database for Strapi | `$TB/postgres` |
| `tbbe` | Strapi backend: login, licences, publishing, registration email | `$TB/tbbe` |
| `tbwwwp` | website: sales, sign-up, profile, orders | `$TB/tbwww` |
| `tbhelpapp` | Timebars Cloud (dashboards, notifications) and the AI service behind Ask AI, AI Create and the help assistant; holds your Gemini key | `$TB/tbhelp` |
| `tbrun` | the Agilebars / Timebars / Costbars app, every hostname (works offline after first load) | `$TB/tbrun` |
| `cloudflared` | *tunnel method* — Cloudflare Tunnel for public HTTPS addresses | `$TB/cloudflared` |
| `tbproxy` | *proxy method* — Caddy: answers every address on this server with free Let's Encrypt certificates | `$TB/proxy` |

**Every stack works the same way.** Same folder and file sets:

| File | What | Who writes it |
|---|---|---|
| `docker-compose.yml`, `.env.example`, `deploy.sh` | from this package | `00-push-to-server.sh` |
| `.env.local` | written for you, never edited by hand | `03-config.sh apply` |
| `.env` | one line: the image tag running now | `deploy.sh` |
| `runtime-config.json` | `tbrun` only, instead of `.env.local`: the app's addresses (no secrets) | `03-config.sh apply` |
| `Caddyfile` | `proxy` only: which name goes to which container (no secrets) | `03-config.sh apply` |

**All your settings are in one file, `$TB/tbapps.conf`**: your addresses (typed once), the keys you paste, and the passwords generated on the server. `03-config.sh apply` writes every `.env.local` and `runtime-config.json` from it (section 7).

To start or update a stack: `cd $TB/<stack> && ./deploy.sh` and type the tag from `VERSION.md`.To change a setting: edit `tbapps.conf`, then `bash $TB/scripts_v1/03-config.sh apply` — it recreates thecontainers whose settings changed. Images are never rebuilt for your server.

All containers share one Docker network, **`tbnet`**, and reach each other by name. Their ports are bound tothe server itself (`127.0.0.1`) — nothing is reachable from the network until you publish it through thetunnel, the proxy or your own reverse proxy (section 8).

Project data lives in each user's browser; the server holds accounts, licences and published data.

## 2. How the installation works

| Who | Where | Does what |
|---|---|---|
| **Your server administrator** | the server | provides a server that meets section 4, under your organisation's own policies (patching, firewall, SSH, hardening) |
| **You (installer)** | your admin workstation | keeps this package (clone or release download), sends it to the server with one command (section 5), and runs every other step from an SSH session |
| **The scripts in this package** | the server | install Docker and the Timebars stack, generate secrets, back up and restore |


**Two ways to deploy** — choose one per server; everything else is the same:

| | Tunnel method (section 8.1) | Proxy method (section 8.3) |
|---|---|---|
| For | the owner of the whole solution — Timebars Ltd. on `timebars.com` and `rlan.ca` | an organisation running its own copy on its own domains |
| Addresses | one domain; staging adds `s` to every name (`pmrms`, `be2s` …) | each environment — PROD, STAGING, DEV or TRAINING — on its own server and domain (`tb.example.com`, `tb.example-staging.net`) |
| HTTPS | Cloudflare: an outbound tunnel, no open ports | Caddy on this server, free Let's Encrypt certificates, ports 80/443 open |
| Settings | `03-config.sh new` | `03-config-proxy.sh` |
| Swap servers | move the tunnel token to the other server | point the DNS records (or the DigitalOcean Reserved IP) at the other server |

The stack folders must be on the server because Docker runs there and reads them locally. Secrets
are generated on the server and never leave it — not to your workstation, not into Git.

**What you need before you start**

| Item | Notes |
|---|---|
| Admin workstation on the same network | Linux, macOS, or Windows with OpenSSH; `git` or a release download of this package; `rsync` |
| Your hostnames | one per product (e.g. `pmrm.example.com`), plus the backend, the website and Timebars Cloud — section 2.1 |
| DNS and HTTPS | **your responsibility** — a Cloudflare account with your domain (section 8.1), a domain whose DNS records point at this server for the proxy (section 8.3; Appendix A shows one way), or your own DNS, reverse proxy and certificates (section 8.2) |
| Docker Hub access | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token |
| Your keys | a Google Gemini key, a SendGrid key; a Cloudflare tunnel token (tunnel method only); Stripe keys only if you sell licences — section 2.1 says where to get each |

On your workstation:
```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown      # or unpack a release download to ~/tbown
cd ~/tbown
```

### 2.1 The settings you will need — read this before you start

Every setting lives in one file, `tbapps.conf` (section 7.1). `03-config.sh new` writes it for you from your domain; you then paste a few keys. This section says what each setting is, why it is needed and where to get it, so you can collect them before the installation day.

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

Every address needs a DNS name pointing at this server — a Cloudflare published application (section 8.1) or a record on your own DNS and proxy (section 8.2). `apply` works out everything that depends on them: the URLs each container uses, the list of browser addresses Strapi accepts (CORS) and the app's site list.

**Part 1, proxy method only — written by `03-config-proxy.sh`**

| Setting | Example | What it is |
|---|---|---|
| `PUBLIC_ACCESS` | `proxy` | the proxy method (section 8.3). Not in the file = the tunnel method |
| `ENVIRONMENT` | `STAGING` | `PROD`, `STAGING`, `DEV` or `TRAINING`. Shown by the checks and in backup folder names. Not `PROD`: every address tells search engines to stay away, and a live Stripe key is flagged |
| `ACME_EMAIL` | `admin@example.com` | Let's Encrypt writes here if a certificate cannot be renewed |
| `BARE_DOMAIN` | `example.com` | the bare domain, redirected to the website (`https://www.example.com`) |

Every proxy address must be a **public** DNS name: Let's Encrypt cannot certify internal-only names such as `tb.company.internal` — those need your own proxy and certificates (section 8.2).

**Part 2 — keys you get and paste**

| Setting | Needed for | Where to get it |
|---|---|---|
| `TUNNEL_TOKEN` | tunnel method only: public HTTPS addresses through Cloudflare (no open ports) | [one.dash.cloudflare.com](https://one.dash.cloudflare.com) → *Networks* → *Tunnels* → **Create a tunnel** → *Cloudflared* → name it after the server → *Choose your environment*: **Docker**. The page shows `docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJh…` — copy only the long value after `--token` (it starts with `eyJ`). For an existing tunnel: *Tunnels* → the tunnel → *Configure* shows the same command. One tunnel and token per server. Leave empty if you use your own reverse proxy (section 8.2) |
| `GEMINI_API_KEY` | Ask AI, AI Create, the help assistant | [aistudio.google.com](https://aistudio.google.com) → **Get API key** → *Create API key* (in a Google Cloud project you own) → copy it (starts with `AIza`). In the Google Cloud console restrict the key to the *Generative Language API*, and add billing with a budget alert if you expect more than the free tier. Empty = AI features off |
| `SENDGRID_API_KEY` | registration confirmation and password-reset emails, sent by Strapi | [twilio.com/en-us/sendgrid](https://www.twilio.com/en-us/sendgrid) → sign up → *Settings* → *Sender Authentication*: verify your `EMAIL_FROM` address (single sender) or your whole domain → *Settings* → *API Keys* → **Create API Key**, *Restricted Access* with **Mail Send** → copy it (starts with `SG.`; shown only once). Empty = no email |
| `STRAPI_ADMIN_TOKEN` | the website (confirming Google / GitHub sign-ups) and Cloud (dashboard sources, Users & Roles) | made **after** Strapi is running: `https://<BACKEND_HOST>/admin` → *Settings* → *API Tokens* → **Create new API token**, *Full access*, *Unlimited* (section 15). Empty until then |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` | only if you sell licences on the website (checkout) | [dashboard.stripe.com](https://dashboard.stripe.com) → *Developers* → *API keys*. For a test or staging server switch to the **sandbox** first (top left) and use `sk_test_…` / `pk_test_…`; for production leave the sandbox and use `sk_live_…` / `pk_live_…`. Leave both empty if you do not sell |

**Part 4 — made on the server by `apply` (you do nothing, but know what they are)**

| Setting | What it protects | If it changes later |
|---|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL's administrator login `pgsuper` (backup and restore scripts, admin use only) | type the new value in `tbapps.conf` and `apply`: it sets the new password in the database |
| `STRAPI_DB_PASSWORD` | the login Strapi uses to open its database (role `strapi`) | the same: `apply` sets it in the database, then recreates `tbbe` so Strapi uses it |
| `POSTGRES_USER`, `STRAPI_DB_NAME`, `STRAPI_DB_USER` | the names: `pgsuper`, database `strapi`, role `strapi` | **never change** once the database exists — `apply` refuses |
| `APP_KEYS` | signs Strapi's session cookies (four values) | users are signed out once |
| `ADMIN_JWT_SECRET` | signs Strapi admin-panel logins | admins are signed out once |
| `JWT_SECRET` | signs the logins of app and website users | every user is signed out once |
| `API_TOKEN_SALT` | protects Strapi API tokens | every API token (e.g. `STRAPI_ADMIN_TOKEN`) stops working — make new ones |
| `TRANSFER_TOKEN_SALT` | protects Strapi data-transfer tokens | transfer tokens stop working |
| `WWW_NEXTAUTH_SECRET`, `CLOUD_NEXTAUTH_SECRET` | sign the website's and Cloud's session cookies | users of that site are signed out once |
| `PGADMIN_DEFAULT_PASSWORD` | the optional pgAdmin page | — |

`apply` makes each one once with a strong random value and never changes it on its own. If part 4 is empty on a server that is already running (the file was lost, renamed or made again with `new`), `apply` takes the values the server uses now from its `.env.local` files instead of making new ones — nothing gets locked out. To make a value by hand: `openssl rand -base64 32`. When you move an installation to a new server, bring its `tbapps.conf` along — the same part 4 keeps every login and token working.

**Three different passwords — do not mix them up**

| Password | Who uses it | Where it is kept | How to change it |
|---|---|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL administrator `pgsuper` | `tbapps.conf` part 4 | edit `tbapps.conf`, `03-config.sh apply` |
| `STRAPI_DB_PASSWORD` | Strapi, to open its database `strapi` | `tbapps.conf` part 4 | edit `tbapps.conf`, `03-config.sh apply` |
| Strapi **admin panel** password | you, at `https://<BACKEND_HOST>/admin` | inside the database (table `admin_users`) — **not** in `tbapps.conf` | `docker exec -it tbbe strapi admin:reset-user-password` (section 11) |

The admin panel accounts are data: loading the seed or a backup (section 11) brings in the accounts and passwords of the server it was made on, and replaces whatever you set before.

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

The server is yours: your administrator builds, patches and secures it under your organisation's policies. The Timebars stack needs the **end state** below; how it is reached is your choice. Each row has a check you can run from your workstation.

| # | The stack needs | Check (from your workstation) |
|---|---|---|
| 4.1 | Ubuntu 24.04 or 26.04 LTS, 64-bit, kept patched (security updates applied) | `ssh myserver lsb_release -ds` |
| 4.2 | At least 2 CPU cores, 4 GB RAM, 100 GB disk; swap on a 4 GB server | `ssh myserver 'nproc; free -h; df -h /'` |
| 4.3 | Correct time, synchronised (NTP) | `ssh myserver timedatectl \| grep synchronized` → `yes` |
| 4.4 | A fixed address, and outbound internet to Docker Hub (and Cloudflare, if used) | `ssh myserver curl -sI https://registry-1.docker.io/v2/ \| head -1` → `401` (reachable) |
| 4.5 | An admin user with `sudo`, key-only SSH from your admin network | `ssh -o PubkeyAuthentication=no myserver` is refused |
| 4.6 | Host firewall: inbound SSH from the admin network only (plus 80/443 for the proxy method, section 8.3, or your own proxy on this server, section 8.2) | `ssh -t myserver sudo ufw status` (or your firewall's equivalent) |
| 4.7 | Installed: `curl`, `ca-certificates`, `rsync`, `tar`, `openssl`, `python3` | `ssh myserver 'command -v curl rsync tar openssl python3'` |
| 4.8 | Docker is **not** pre-installed by another method (snap, distribution packages) — section 6 installs it | `ssh myserver 'command -v docker'` prints nothing |

> **Firewall note for your administrator.** The compose files publish container ports on
> `127.0.0.1` only — except `tbproxy` (proxy method), which is meant to be reached on 80/443. Keep it that way: Docker writes its own firewall rules, and a port published on
> all addresses is reachable from the network **even when the host firewall denies it**. A network
> firewall in front of the server needs no inbound rule except SSH (and 80/443 for your own proxy).

### 4.9 A new cloud server

No administrator and a fresh cloud server (for example a DigitalOcean droplet)? `00-prep-new-server.sh` brings it to the end state above in one step — see Appendix B. Appendix A shows how to get the server and a domain.

## 5. Send the package to the server

Decide where Timebars goes on the server: the **parent folder** where you keep Docker apps, given as a
**full path starting with `/`** — for example `/docker/compose`, `/srv/docker` or `/home/<you>`. The script creates a folder **`tbApps`** inside it and puts everything there (e.g. `/docker/compose/tbApps`). Timebars then never mixes with your other apps.

On your workstation, in your copy of the package:
```bash
cd ~/tbown && git pull                                  # latest version (skip for a release download)
bash archive/scripts_v1/00-push-to-server.sh myserver /docker/compose
```
Leave the folder out and the script asks for it; it remembers your answer for that server next time. If the parent belongs to root, the script tells you the one `sudo` command to run on the server first.

It copies the stack folders, the scripts and the seed data, and sets **`TB`** to the tbApps folder in your `~/.bashrc` on the server — every command in this guide uses `$TB` (e.g. `cd $TB/tbbe`). Run it again whenever the package is updated: it never overwrites or deletes what belongs to the server (`tbapps.conf`, the `.env.local` files, `runtime-config.json`, uploaded files). If the server is your workstation itself, use `local` as the server name.

All remaining steps run **on the server**. Open a session and stay in it:
If terminal session was already running, exit and ssh into the target server again to engage the $TB. Test if it works run echo $TB it should return full path to the tbApps package.
```bash
ssh myserver
echo $TB                                                # e.g. /docker/compose/tbApps
```

### 5.1 Installing on the machine you are working on (no SSH)

When the package and Docker are on the **same machine** — you install on the computer you are sitting at, or your copy of the package is already on the server — there is nothing to connect to: no SSH server is needed and section 3 does not apply. Use the word `local` instead of a server name:
```bash
cd ~/tbown                                              # wherever your copy of the package is
bash archive/scripts_v1/00-push-to-server.sh local /docker/compose
source ~/.bashrc                                        # this terminal learns $TB (new terminals have it)
echo $TB                                                # /docker/compose/tbApps
```
`local` is not a host name: `ssh local` or `ssh <this machine>` will fail (*Could not resolve hostname*,
*Connection refused*) and is not needed. Skip every `ssh myserver` / `exit` line in this guide and run
the commands in your own terminal. `echo $TB` printing nothing only means this terminal was open before
the script set it: run `source ~/.bashrc`.

## 6. Install Docker

```bash
sudo bash $TB/scripts_v1/01-install-docker.sh
exit                                            # log out and back in, so docker works without sudo
```
```bash
ssh myserver
id -nG                                          # must list "docker" - if not, log out and in again
docker version && docker compose version        # Client and Server versions both shown
docker login -u <your Docker Hub user>          # paste your read-only access token
```
In my case it is: docker login -u jimecox807
Enter the docker PAT password file for your account

The script installs `curl` and `ca-certificates` (as Docker's own instructions do), then Docker Engine and the Compose plugin from Docker's own repository — Ubuntu's packages only if Docker has none yet for your release; the last line says which (`from: docker packages`). It turns on log rotation for every container and adds your user to the `docker` group. If Ubuntu's `docker.io` is already installed and no containers exist yet, it is replaced by Docker's packages. Your administrator may prefer to install Docker under your own standards — the stack needs Docker Engine 24+ with the Compose plugin (`docker compose`).

## 7. Volumes, network and settings

From here on, run every script **without `sudo`**, as your admin user — the files they create must belong to you, in `$TB`. If a script says it cannot use Docker, log out and back in (section 6).

```bash
bash $TB/scripts_v1/02-create-volumes.sh      # database volumes and the network tbnet
```

### 7.1 Make your settings file, `tbapps.conf`

agile-pm-rm-ppm.com

Every setting of the installation is in **one plain-text file**. You type each address once; every other value (the URLs each container needs, Strapi's allowed origins, the app's runtime-config.json`) is worked
out from it.

**a. Answer a few questions** — on your workstation (in your copy of the package) or on the server:
```bash
bash archive/scripts_v1/03-config.sh new              # workstation: writes tbapps.conf in the package folder
bash $TB/scripts_v1/03-config.sh new          # or on the server: writes $TB/tbapps.conf
```
It asks your domain (e.g. `example.com`), an optional letter added to every name (`s` for a staging server: `agiles`, `be2s` …), proposes the six addresses — press Enter to accept each — and asks whether to add the short `ab` / `tb` / `cb` addresses as optional extras. Run it again later to change the addresses: it keeps part 2 (your keys), part 3 and part 4 (the passwords), and saves the old file next to it.

**Proxy method (section 8.3)?** Use its own questions instead of `new`:
```bash
bash archive/scripts_v1/03-config-proxy.sh            # workstation, or on the server: bash $TB/scripts_v1/03-config-proxy.sh
```
It asks which environment this server is (PROD, STAGING, DEV or TRAINING), that environment's domain, process names (`agile` / `pmrm` / `ppm`) or initials (`ab` / `tb` / `cb`) for the three apps, whether to install the offline service worker, and an email for Let's Encrypt. The bare domain is always redirected to the website. The rest of this section is the same for both methods.

**b. Paste your keys** into part 2 of the file, in any text editor: the tunnel token (tunnel method, section 8.1), your
Gemini key (section 13), your SendGrid key. Leave empty what you do not use; `STRAPI_ADMIN_TOKEN` comes
later (section 15).

**c. Put it on the server** (only if you made it on the workstation) — open the file there and paste the
whole text in one go:
```bash
nano $TB/tbapps.conf                       # paste, then Ctrl+O, Enter (save), Ctrl+X (leave)
```

**d. Apply it**:
```bash
bash $TB/scripts_v1/03-config.sh apply
```
`apply` checks the file (hostnames only, no `https://`, no address used twice, emails look like emails),
generates every password and key that is made on the server — the first time only, kept from then on —
writes them into part 4 of `tbapps.conf`, sets a changed `POSTGRES_PASSWORD` or `STRAPI_DB_PASSWORD` in
the running database, and writes each stack's `.env.local` and
`tbrun/runtime-config.json` (and, for the proxy method, `proxy/Caddyfile`). It lists what changed per stack and, if those containers are already
running, offers to recreate them. `bash $TB/scripts_v1/03-config.sh check` shows the same list without
writing anything.

The file has four parts:

| Part | What | Who |
|---|---|---|
| 1. Your addresses | `APP_AB_HOST`, `APP_TB_HOST`, `APP_CB_HOST`, `APP_OFFLINE`, `EXTRA_APP_HOSTS` (e.g. `ab.example.com:AB tb.example.com:TB`), `BACKEND_HOST`, `WEBSITE_HOST`, `CLOUD_HOST`, `EMAIL_FROM` … | you (`new` fills them) |
| 2. Keys you paste | `TUNNEL_TOKEN`, `GEMINI_API_KEY`, `SENDGRID_API_KEY`, `STRAPI_ADMIN_TOKEN`, Stripe (section 2.1) | you |
| 3. Optional extras | any other setting for one stack, e.g. `TBHELP__AI_REQUIRE_LOGIN=false` | you, rarely |
| 4. Made on the server | database passwords, Strapi secrets, sign-in secrets | `apply` — edit only to change a database password (section 2.1) |

**Keep a copy of `tbapps.conf` in your password manager or secrets vault**: it holds every password of the installation, and a restore or a move to another server starts from it. It is `chmod 600`; edit it with `nano $TB/tbapps.conf` as your own user (no `sudo`). Typing only a file's path tries to *run* it and answers *Permission denied* — put `nano` in front.

**Lost or renamed `tbapps.conf`?** The containers keep running — they read their `.env.local` files, not `tbapps.conf` — but `apply` stops with *No tbapps.conf*. Rename it back (`ls $TB/tbapps.conf*` shows the copies). If it is gone, run `03-config.sh new` (proxy method: `03-config-proxy.sh`) and `apply`: part 4 is filled from the server's current settings, so every password stays as it is.

**A server set up before `tbapps.conf`** (settings in `.env.local` files): make the file from what is there, keeping every password, then check that nothing would change:
```bash
bash $TB/scripts_v1/03-config.sh import && bash $TB/scripts_v1/03-config.sh check
```

## 8. Public addresses: DNS, HTTPS, the tunnel or the proxy

Do this **now**, before starting the other stacks, so every address exists while you install: after each stack in sections 9–14, `07-check-urls.sh` (section 16) tests it from the outside. Until a stack is up its address answers 502 — expected.

Choose **one** of the three ways (section 2 compares the first two). Every way, users reach the apps only over HTTPS (required for offline mode).

### 8.1 Cloudflare Tunnel (no open ports)

1. In Cloudflare Zero Trust → Networks → Tunnels, create a tunnel (one per server) and paste its token as    `TUNNEL_TOKEN=` in `tbapps.conf`, then `bash $TB/scripts_v1/03-config.sh apply`.
2. `cd $TB/cloudflared && ./deploy.sh` — it shows *Registered tunnel connection*, and the tunnel shows    *Healthy* in the dashboard.
3. Add one *published application* per hostname, service type **HTTP**, pointing at the **container    name** — not `localhost` (inside cloudflared that is cloudflared itself) and not an IP address (the    ports are bound to `127.0.0.1`). The same routes work on any server running these stacks:

| Hostname (example) | Service |
|---|---|
| `agile.example.com`, `pmrm.example.com`, `ppm.example.com` (every app hostname) | `http://tbrun:80` |
| `be2.example.com` | `http://tbbe:1337` |
| `www.example.com` | `http://tbwwwp:3001` |
| `cloud.example.com` (Timebars Cloud: dashboards, notifications, help) | `http://tbhelpapp:3010` |
| *optional:* `help.example.com`, `dashboard.example.com`, `pubsets.example.com` | `http://tbhelpapp:3010` (each forwards to its page on `cloud.example.com`) |

Keep *Rocket Loader* off and do not add *Cache Everything* rules for these hostnames.

**A tunnel container you already run** (another name, e.g. `cloudflare`, started from Portainer or another compose file — leave `TUNNEL_TOKEN` empty): put it on the Timebars network, so it can reach the containers
by name:
```bash
docker network connect tbnet cloudflare     # your tunnel container's name
```
Do this again whenever `tbnet` is removed and made again (a clean reinstall): the container is not put back on the network by itself, and restarting it does not help. `06-health-check.sh` shows *tunnel container … is NOT on tbnet* when this is needed — the symptom is every public address answering **502** while `06` shows all containers healthy.

**Moving to another server** keeps every route: stop cloudflared on the old server
(`cd $TB/cloudflared && docker compose down`), then put the same token in the new server's `tbapps.conf`, `03-config.sh apply` and `./deploy.sh` in its cloudflared folder. Never run one token on two servers at once — Cloudflare would split
visitors between them.

### 8.2 Your own DNS, reverse proxy and certificates

See [`docker/proxy-example/README.md`](../docker/proxy-example/README.md): which local address each hostname points at, where your certificate and key go, and an example nginx configuration. DNS records, certificates and their renewal are your responsibility. This is also the way for internal-only names (`tb.company.internal`) with certificates from your own certificate authority.

### 8.3 The proxy on this server (Caddy, Let's Encrypt)

Users reach this server directly. The `tbproxy` container (Caddy) answers ports 80 and 443, gets a free Let's Encrypt certificate for every address, renews each one by itself, and passes every name to its container over `tbnet`. Its settings file, `$TB/proxy/Caddyfile`, is written by `03-config.sh apply` from `tbapps.conf` (made with `03-config-proxy.sh`, section 7.1). On a new cloud server, Appendix B walks
through all of it.

1. **Ports 80 and 443 open** to the internet: the host firewall (`sudo ufw allow 80,443/tcp`;
   `00-prep-new-server.sh --web` does it) and any cloud firewall in front of the server.
2. **DNS records** — one `A` record per address, pointing at this server's public IP, at your registrar
   (Appendix A: Rebel.ca). The list, and whether each record works yet:
   ```bash
   bash $TB/scripts_v1/03-config.sh dns          # on DigitalOcean it finds the IP; elsewhere: dns <IP>
   ```
   Run it until every line shows `[x]`. New records can take a few minutes to appear.
3. **Start the proxy** once every name resolves:
   ```bash
   cd $TB/proxy && ./deploy.sh                # Enter = the Caddy tag in VERSION.md
   ```
   It shows the first certificates (*certificate obtained successfully*); a name whose DNS record is
   missing shows *could not get certificate* and is retried by itself — fix the record, nothing else.

| Address | The proxy passes it to |
|---|---|
| the three app addresses (process names or initials) | `tbrun:80` |
| `be2.<domain>` | `tbbe:1337` |
| `www.<domain>` | `tbwwwp:3001` |
| `cloud.<domain>` | `tbhelpapp:3010` |
| `<domain>` (bare) | redirect to `https://www.<domain>` |

**Changing an address** later: edit `tbapps.conf`, `03-config.sh apply` (it reloads Caddy without dropping connections, and Caddy gets the new certificate), and add the DNS record. Caddy's certificates are kept in the Docker volume `tbproxy_data`: keep it — Let's Encrypt limits how many certificates one domain may get per week, so a proxy that loses them on every reinstall can be refused for days.

## 9. Deploy Postgres and Database Container

```bash
cd $TB/postgres && ./deploy.sh      # Enter = the tag in VERSION.md (16)
docker logs tbpgdb | grep initdb         # "created role strapi and database strapi"
```
On first start an empty database is created for Strapi, with its own login (not the superuser).

The log line `initdb: warning: enabling "trust" authentication for local connections` is the official PostgreSQL image's default: it applies only to connections *inside* the container (used by the backup and restore scripts through `docker exec`). Connections from other containers, such as Strapi, need the password, and the port is reachable only from the server itself (`127.0.0.1:5433`).

## 10. Deploy Strapi backend container

```bash
cd $TB/tbbe
sudo chown -R 1000:1000 public/uploads
./deploy.sh                               # waits for Strapi to start (a minute or two); /_health answers 204
```
Create the first administrator at `https://<your backend address>/admin` once the public address works (section 8), or now through an SSH tunnel from your workstation:
`ssh -N -L 1337:localhost:1337 myserver`, then open `http://localhost:1337/admin`.

Expected messages in the log on a first start:

| Message | Meaning |
|---|---|
| `API key does not start with "SG."` | `SENDGRID_API_KEY` is empty — Strapi runs, but sends no email |
| administration panel at `http://0.0.0.0:1337/admin` | the address Strapi listens on inside the container; use your public address or the SSH tunnel |

**Next, load the seed data (section 11)** so the website has its content (products, help articles, FAQ).

## 11. Load the seed data or a backup

```bash
bash $TB/scripts_v1/04-restore.sh            # loads $TB/seed/seed.dump and seed-uploads.tar.gz
```
The same script restores your own backups (section 17). It stops Strapi, drops and re-creates the Strapi database (`STRAPI_DB_NAME`, normally `strapi`, owned by role `strapi`), loads the dump into it — whatever database name the dump came from — starts Strapi again and lists the tables that hold rows. Your `tbapps.conf` passwords do not change: the dump holds data, not database logins.

After the seed is loaded:
- **Strapi admin panel** (`https://<backend>/admin`): the admin accounts came with the data, with the   passwords of the server the dump was made on. See which accounts there are, and set your own password:
  ```bash
  docker exec tbpgdb psql -U strapi -d strapi -Atc "select email from admin_users"
  docker exec -it tbbe strapi admin:reset-user-password      # asks for the email, then the new password
  ```
  Keep that password in your vault. **Every restore brings the dump's passwords back** — run the reset  again after each one. (This is the admin panel login only; it is not `POSTGRES_PASSWORD` or
  `STRAPI_DB_PASSWORD`.)
- API tokens stored in the seed were made under Timebars Ltd.'s secrets and do not work on your
  server — section 15 makes the one the website and Cloud need.
- In the app, sign in with a demo account: *Show License* shows the product and its limits.

Check that Strapi reads the restored data:
```bash
docker exec tbpgdb psql -U strapi -d strapi -Atc "select 'users', count(*) from up_users union all select 'products', count(*) from products"
bash $TB/scripts_v1/07-check-urls.sh       # the Strapi lines are OK now
```

## 12. Website

```bash
cd $TB/tbwww && ./deploy.sh          # Enter = the tag in VERSION.md
```
Every address and key comes from `tbapps.conf` (written to `tbwww/.env.local`) at run time. Sign-in with email and password works against your backend. Google / GitHub / Facebook sign-in and payments stay off until you add their keys (*Administrators Guide*). The Personal and Enterprise dashboards are on Timebars Cloud (13); old `/dashboard` links on the website forward there.

## 13. Timebars Cloud and the AI service

Ask AI, AI Create and the help assistant run in this container, with the Cloud pages (dashboards, notifications). It keeps your Gemini key on the server (never in the browser), and answers only users who are logged in to your Timebars Cloud (Strapi).

1. Create a Gemini key in your own Google account (aistudio.google.com → *API keys*), restricted to the  Generative Language API. Turn on billing and a budget alert if you expect more than the free tier.
2. Put it in `tbapps.conf` as `GEMINI_API_KEY=` (if you did not already in section 7), then
   `bash $TB/scripts_v1/03-config.sh apply`.
3. Deploy:
```bash
cd $TB/tbhelp && ./deploy.sh
```
It checks that the AI routes answer. The AI service needs **no public address of its own**: the browser calls the app's address and the app forwards `/ai/` to this container over `tbnet`. A site with no Strapi (no login) adds `TBHELP__AI_REQUIRE_LOGIN=false` to `tbapps.conf` part 3, applies, and keeps the server reachable from its own network only.

## 14. The app

One image serves every app hostname — with or without offline mode — and every customer. Its addresses are in `tbrun/runtime-config.json`, written by `03-config.sh apply` from `tbapps.conf`:
```bash
cd $TB/tbrun && ./deploy.sh     # Enter = the tag in VERSION.md
```
Each app address in `tbapps.conf` becomes a `sites` row that maps the hostname to its product (`AB` Agilebars, `TB` Timebars, `CB` Costbars); the three main ones work offline when `APP_OFFLINE=yes`, the `EXTRA_APP_HOSTS` ones never. A hostname that is not listed gets no product. After a change: edit `tbapps.conf`, apply, then reload the page twice.

In Cloudflare, every app hostname points at `http://tbrun:80` (section 8.1); an old route to `tbrun-offline` answers 502.

## 15. The Strapi API token

The website (confirming Google / GitHub sign-ups, docs sync) and Timebars Cloud (dashboard sources, Users & Roles) call Strapi with a server-side token.

1. Open `https://<your backend address>/admin`, sign in, then Settings → API Tokens → **Create new API token**:
   name `<server>-server`, duration **Unlimited**, type **Full access**. Save and copy it.
2. Paste it as `STRAPI_ADMIN_TOKEN=` in `tbapps.conf`, then apply and let it recreate `tbwwwp` and   `tbhelpapp`:
```bash
nano $TB/tbapps.conf
bash $TB/scripts_v1/03-config.sh apply
```
This is how every setting changes: edit `tbapps.conf`, apply — no new image.

## 16. Check the installation

```bash
bash $TB/scripts_v1/06-health-check.sh      # inside the server: every container, its health and running tag
bash $TB/scripts_v1/07-check-urls.sh        # from outside: every public address, through the tunnel or proxy
```
`06` compares each container's tag with `VERSION.md`. `07` reads your addresses from the settings files (written from `tbapps.conf`: every app address including the extras, Strapi, the website and Cloud) and checks each page, the AI route, the offline worker, `runtime-config.json`, the dashboard redirect and Strapi's CORS answer for every app address. A FAIL line says what to fix (a missing route, a wrong container name, a missing CORS origin).

Then in a browser: open each app address (the product title matches the hostname), sign in, check *Show License*, publish a dataset and open it on the dashboard, and ask the help assistant a question (Ask AI works only when you are signed in). On an app address, DevTools → Application → Service Workers shows `sw.js` activated; tick *Offline* and press F5 — the app still loads.

## 17. Backups

```bash
bash $TB/scripts_v1/05-backup.sh           # try it once
crontab -e                                   # then schedule it nightly:
# 15 2 * * * /bin/bash $HOME/docker/scripts_v1/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup (proxy method: the folder name ends with the environment, e.g. `2026-10-12_0215_STAGING`) holds the Strapi database, its uploads, `tbapps.conf` and the files written from it (the folder is private to your admin user). Copy `~/backups/timebars` off the server with your normal backup system, and practise a
restore.

Users' own project data lives in their browsers: their backup files and synced spreadsheets go into your document management system (see the *Data Synchronization, Backup, Recovery and Retention* guide).

## 18. Updates and rollback

| What | How |
|---|---|
| This package | workstation: `git pull` (or new release), then `bash archive/scripts_v1/00-push-to-server.sh myserver` |
| Any container | server: `cd $TB/<stack> && ./deploy.sh` and type the new tag from `VERSION.md`; back up first for `tbbe` |
| Roll back | the same, with the previous tag (`deploy.sh` shows the one running now) |
| A setting (address, key) | edit `tbapps.conf`, then `bash $TB/scripts_v1/03-config.sh apply` (it recreates what changed) |
| PostgreSQL major version | backup → new empty volume → `./deploy.sh` with the new major tag → restore (`deploy.sh` refuses a major change on a database with data) |
| Ubuntu, firewall, SSH | your administrator, under your policies |

**From an earlier copy of this package** (folders `tbrunoffline` and `tbwwwp`, settings in `.env`, networks `postgres_tbpg_net` and `tbhelp`): run `00-push-to-server.sh`, then on the server, for each old folder, `docker compose down`; make `tbapps.conf` with `03-config.sh new`, and copy the database passwords and Strapi secrets from the old `postgres/.env` and `tbbe/.env` into its part 4  `POSTGRES_PASSWORD`,`STRAPI_DB_PASSWORD`, `APP_KEYS`, `API_TOKEN_SALT`, `ADMIN_JWT_SECRET`, `TRANSFER_TOKEN_SALT`, `JWT_SECRET`) before the first `apply`; then `bash $TB/scripts_v1/02-create-volumes.sh` and `./deploy.sh` in each stack,
database first. Delete the old folders and networks (`docker network rm postgres_tbpg_net tbhelp`) once everything is green. Change the tunnel routes to `http://tbrun:80` for the app hostnames.

**From the first `tbApps` layout** (settings typed into each `.env.local`): `bash $TB/scripts_v1/03-config.sh import`, then `check` — it should show no changes. From then on edit `tbapps.conf` only.

## 19. Troubleshooting

| Symptom | Fix |
|---|---|
| `kex_exchange_identification: Connection reset by peer` | your workstation offered too many keys; use `IdentitiesOnly yes` (section 3) and wait a few minutes |
| `00-push-to-server.sh`: *rsync is missing* | install `rsync` on the workstation or ask the administrator to install it on the server (section 4.7) |
| `apt`: *Temporary failure resolving* | the server has no DNS — your administrator sets gateway and DNS servers |
| `permission denied ... docker.sock` | log out and back in after section 6 |
| Docker install says *Cannot reach download.docker.com* | the server has no internet access to Docker (proxy, firewall); fix it and run the script again |
| `tbpgdb` keeps restarting; log: *database files are incompatible with server … initialized by PostgreSQL version 14* | the volume `postgres_db` holds a database from an earlier install. Not needed: `cd $TB/postgres && docker compose down; docker volume rm postgres_db; bash $TB/scripts_v1/02-create-volumes.sh; ./deploy.sh`. Needed: back it up with the old version first, then restore it into the new one (`04-restore.sh`) |
| Strapi cannot reach the database (`password authentication failed for user "strapi"`) | the database has another password than `tbapps.conf` part 4 holds. Restore the old `tbapps.conf` from your vault or backup and apply — or keep the new value and apply: it sets it in the database |
| Every public address answers 502 (`07`), but `06` shows everything healthy | the tunnel container is not on `tbnet` (typical after a clean reinstall, which removes and re-creates `tbnet`): `docker network connect tbnet <tunnel container>` — `06` names it (section 8.1) |
| `03-config.sh apply`: *No tbapps.conf* | it was renamed or moved — `ls $TB/tbapps.conf*` and rename it back; or `03-config.sh new`, then apply (it keeps the server's passwords) |
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
| `docker compose`: *env file .env.local not found* | `bash $TB/scripts_v1/03-config.sh apply` (section 7.1) |
| Strapi admin login fails; `docker logs tbbe` shows *originList.split is not a function* | the backend's own address was not an allowed origin. Fixed in `03-config.sh apply` (it now lists `BACKEND_HOST` too) and in tbbe images after 2026.10.09: run `bash $TB/scripts_v1/03-config.sh apply` and recreate tbbe |
| Strapi admin login fails with the right page shown | wrong email or password for the account in the restored data (a restore brings back the dump's admin passwords, section 11) — list the admin accounts: `docker exec tbpgdb psql -U strapi -d strapi -Atc "select email, is_active, blocked from admin_users"`, and reset a password with `docker exec -it tbbe strapi admin:reset-user-password` (it asks for the email and the new password). After 5 failed tries Strapi refuses every login for that email for 5 minutes — wait before trying again |
| `03-config.sh apply`: *Stopped: the database already exists and … would change* | a database **name** in part 4 (`POSTGRES_USER`, `STRAPI_DB_NAME`, `STRAPI_DB_USER`) differs from the running database — put back the value shown in `$TB/postgres/.env.local`. Passwords may change; names may not |
| Proxy: `07-check-urls.sh` answers 000 for an address | the DNS record is missing or points elsewhere (`03-config.sh dns`), ports 80/443 are closed (`sudo ufw status`, the cloud firewall), or the certificate is not there yet (`docker logs tbproxy \| grep -i certificate`) |
| Proxy: *could not get certificate* in `docker logs tbproxy` | Let's Encrypt could not reach this server for that name: fix its DNS record or the firewall; Caddy retries by itself. *too many certificates* = the weekly limit — wait, and keep the `tbproxy_data` volume from now on |
| Proxy: every name points to the same unknown address (`03-config.sh dns`) | the registrar's parking or default records (often `*` and `@`) — delete them (Appendix A) |
| Proxy: `deploy.sh` says ports 80/443 are in use | another web server runs on this server (`sudo ss -ltnp`): stop it, or use your own proxy (section 8.2) |
| Proxy: `apply` says *Let's Encrypt only certifies public DNS names* | an address ends in `.internal`, `.local`, `.lan` …: use public names, or your own proxy and certificates (section 8.2) |
| Proxy: the browser shows a certificate warning | the certificate is not issued yet, or a stale `AAAA` (IPv6) record sends some visitors elsewhere — `03-config.sh dns` flags it |

For help, send the output of `bash $TB/scripts_v1/06-health-check.sh` and
`docker logs --tail 100 <container>` — never send `tbapps.conf`, `.env.local` files, tokens or passwords.

---

# Appendices

## Appendix A. A domain and a server: Rebel.ca and DigitalOcean

*Optional* — for when you have neither a domain nor a server yet. We use **Rebel.ca** (a Canadian
registrar) for the domain and its DNS records, and **DigitalOcean** (DO) for the server. Any registrar
(Namecheap, GoDaddy, Cloudflare Registrar …) and any cloud (Hetzner, Linode/Akamai, Vultr, AWS Lightsail,
Azure, Google Cloud …) works the same way: you buy a name, rent an Ubuntu server, and point one DNS record
per address at the server's IP. Menu names below are as of October 2026 and change now and then.

### A.1 DigitalOcean: the server first (you need its IP for the DNS records)

1. **Account** — sign up at [digitalocean.com](https://www.digitalocean.com), confirm your email, add a
   payment method, and turn on two-factor authentication (*Settings → Security*).
2. **Project** — *New Project*, named after the installation (e.g. `Timebars PROD`): keeps its resources
   together.
3. **SSH key** — *Settings → Security → SSH Keys → Add SSH Key*: paste your workstation's public key
   (`cat ~/.ssh/id_ed25519.pub`; make one with `ssh-keygen -t ed25519` if it says *No such file*).
4. **Droplet** — *Create → Droplets*:
   - Region: closest to your users (e.g. Toronto, `TOR1`).
   - Image: **Ubuntu 24.04 (LTS) x64**.
   - Size: *Basic*, at least **4 GB RAM / 2 CPUs** (section 4.2); 8 GB gives room to grow.
   - Authentication: **SSH Key** — tick the key from step 3 (no root password).
   - Enable **backups** (DO keeps whole-server snapshots) and **monitoring** (graphs and alerts).
   - Hostname: something you will recognise, e.g. `tb-prod-1`.
5. **Reserved IP** — *Networking → Reserved IPs*: assign one to the droplet. **This is the IP for your
   DNS records.** It stays the same when you resize the droplet or replace it with a new one (Appendix C),
   so the DNS never has to change.
6. **Cloud Firewall** (recommended) — *Networking → Firewalls → Create Firewall*: inbound `SSH` (TCP 22)
   from your own IP, `HTTP` (80) and `HTTPS` (443) from everywhere; apply it to the droplet. It sits in
   front of the server's own firewall.
7. **Monitoring alerts** — *Monitoring → Create alert policy*: CPU above 80 %, memory above 85 %, disk
   above 80 %, sent to your email.

### A.2 Rebel.ca: the domain and its DNS records

1. **Account** — sign up at [rebel.ca](https://www.rebel.ca) (or sign in), and turn on two-factor
   authentication in your account settings.
2. **Buy the domain** — search for the name, add it to the cart, check out. Keep *WHOIS privacy* on.
   Already own it (e.g. `agile-pm-rm-ppm.com`)? Skip to step 3.
3. **Open the DNS records** — *My Domains* → the domain → **Edit DNS records**.
4. **Delete the parking records.** A new domain points at Rebel's parking page — usually an `A` record for
   `@` and one for `*` (every name), sometimes a `CNAME` for `www`. Delete those; they would send your
   addresses to the parking page. Keep any `MX` and `TXT` records for email.
5. **Add one `A` record per address** — *Host*: the part before your domain (`@` for the domain itself),
   *Points to / Value*: the Reserved IP from A.1, *TTL*: 300 seconds while you set up (3600 once all
   works). **No `AAAA` records** — the droplet's IPv6 is not used, and a stale one breaks certificates.
6. **SendGrid** (section 2.1) — if you authenticate the whole domain for email, SendGrid shows a few
   `CNAME` records: add them here too.

### A.3 Checklist of DNS records

Example for `agile-pm-rm-ppm.com` with **process names** (with **initials**, use `ab`, `tb`, `cb` instead of
the first three). Tick each one off at Rebel:

| ✓ | Type | Host | Points to | For |
|---|---|---|---|---|
| ☐ | A | `agile` | Reserved IP | Agilebars |
| ☐ | A | `pmrm` | Reserved IP | Timebars |
| ☐ | A | `ppm` | Reserved IP | Costbars |
| ☐ | A | `be2` | Reserved IP | Strapi backend |
| ☐ | A | `www` | Reserved IP | website |
| ☐ | A | `cloud` | Reserved IP | Timebars Cloud, AI help |
| ☐ | A | `@` | Reserved IP | the bare domain → redirected to `www` |
| ☐ | — | `*`, parking `@` | *deleted* | Rebel's parking records |

Each environment has its own domain and server: a STAGING server on `agile-pm-rm-ppm-staging.com` (or
`staging.agile-pm-rm-ppm.com`, with `agile.staging` as the host …) gets its own set of records, pointing at
its own IP.

**The authoritative list is your `tbapps.conf`.** Once it is made (Appendix B), this prints exactly the
records it needs and checks each one:
```bash
bash $TB/scripts_v1/03-config.sh dns
```
From your workstation, one name: `dig +short pmrm.agile-pm-rm-ppm.com` (Windows: `nslookup …`) shows the IP.

## Appendix B. A new server with the proxy, start to finish

*Optional* — the whole proxy-method installation on a fresh cloud server (Appendix A), with no server
administrator. Each step points to its section; nothing here replaces them.

### B.1 Prepare the server (as root, once)

`00-prep-new-server.sh` brings a fresh Ubuntu 24.04 / 26.04 server to the end state of section 4: updates
and automatic security updates, the tools in 4.7, an admin user with `sudo` and your SSH key, SSH with keys
only and no root login, the firewall (SSH, and 80/443 with `--web`), time sync and swap. From your
workstation, in the package folder:

```bash
scp scripts_v1/00-prep-new-server.sh root@143.244.175.252:
ssh -t root@ bash 00-prep-new-server.sh jcox --web --ssh-from 174.112.232.28   # an admin name of your choice
```
- It asks a password for the admin user: for `sudo` only — SSH never accepts it. Keep it in your vault.
- Leave out `--ssh-from` if your own address changes; SSH is then open to everyone, keys only (the DO
  Cloud Firewall from A.1 can still narrow it).
- Add `--key "$(cat ~/.ssh/id_ed25519.pub)"` if root has no key on the server.
- At the end it prints the `~/.ssh/config` block for section 3. Add it, and **before closing the root
  session** test from a new terminal: `ssh <server> 'hostname; sudo -v && echo sudo ok'`. Reboot if it
  says so.

Your usual hardening (fail2ban, auditd, your policies) goes on top.

### B.2 The installation

| Step | What | Section |
|---|---|---|
| 1 | Send the package: `bash archive/scripts_v1/00-push-to-server.sh <server> /home/<you>` | 5 |
| 2 | Install Docker, log out and in | 6 |
| 3 | Volumes and network: `bash $TB/scripts_v1/02-create-volumes.sh` | 7 |
| 4 | Settings: `bash $TB/scripts_v1/03-config-proxy.sh` — environment, domain, name style, offline; paste your keys; `bash $TB/scripts_v1/03-config.sh apply` | 7.1 |
| 5 | DNS records at the registrar, until `bash $TB/scripts_v1/03-config.sh dns` shows every name `[x]` | A.2, 8.3 |
| 6 | The proxy: `cd $TB/proxy && ./deploy.sh` — certificates within a minute | 8.3 |
| 7 | Database, Strapi, seed, website, Cloud, app, API token — skip 8.1 | 9 – 15 |
| 8 | Checks: `06-health-check.sh` (shows the environment) and `07-check-urls.sh` | 16 |
| 9 | Nightly backups, copied off the server | 17 |

A session of step 4, for a staging server:
```text
Environment of this server (PROD / STAGING / DEV / TRAINING) [PROD]: STAGING
Domain for the STAGING environment, e.g. example.com or staging.example.com: agile-pm-rm-ppm.com
Address names for the three apps:
  1 = process names   agile.agile-pm-rm-ppm.com  pmrm.agile-pm-rm-ppm.com  ppm.agile-pm-rm-ppm.com
  2 = initials        ab.agile-pm-rm-ppm.com  tb.agile-pm-rm-ppm.com  cb.agile-pm-rm-ppm.com
Which [1]: 1
Proposed addresses:
  Agilebars        agile.agile-pm-rm-ppm.com
  ...
  (redirect)       agile-pm-rm-ppm.com -> www.agile-pm-rm-ppm.com
Use these (Y/n):
Install the service worker, so the apps keep working offline after the first visit (Y/n):
Your email for Let's Encrypt certificate notices [admin@agile-pm-rm-ppm.com]:
```

### B.3 Looking after it

| What | How |
|---|---|
| Certificates | Caddy renews them by itself, about 30 days before they expire; `ACME_EMAIL` hears about problems |
| Caddy updates | a new tag in `VERSION.md` → `cd $TB/proxy && ./deploy.sh` (section 18), like every stack |
| A new or changed address | `tbapps.conf` → `03-config.sh apply` → its DNS record → `03-config.sh dns` |
| Ubuntu updates | security updates install themselves; `sudo apt full-upgrade` and a reboot now and then (the containers start by themselves) |
| Moving to a new server | install the new one (B.1, B.2 with the same `tbapps.conf`, then restore the latest backup, section 11), then move the Reserved IP to it — DNS does not change |

## Appendix C. Growing: bigger and more servers

One server runs everything comfortably for a small organisation. Grow one step at a time, when the DO
monitoring graphs (A.1) say so — usually memory first. Prices change: check your provider's pricing page.

| Step | What | Effort | When |
|---|---|---|---|
| 1. Resize | DO: *Droplet → Resize* to more CPU and RAM (power off, a few minutes). Choose *CPU and RAM only* to be able to size down again; a bigger disk cannot be undone | minutes, no change to the installation | memory or CPU often above 80 % |
| 2. Managed database | move PostgreSQL to **DO Managed PostgreSQL** (daily backups, a standby on request, patching done for you): back up (`05-backup.sh`), restore the dump into the managed database (`pg_restore`, from the droplet), then point Strapi at it with part 3 lines in `tbapps.conf` — `TBBE__DATABASE_HOST=…`, `TBBE__DATABASE_PORT=25060`, `TBBE__DATABASE_USERNAME=…`, `TBBE__DATABASE_PASSWORD=…`, `TBBE__DATABASE_SSL=true` — `apply`, and stop `tbpgdb` | an hour | the database needs its own backups and resilience, or the droplet's disk fills |
| 3. Split the stacks | put stacks on two or three droplets in the same region, talking over DO's private network (VPC): e.g. Strapi alone, website + Cloud + app on another. Each droplet runs its own proxy for its own names, and the DNS records point each name at its droplet | a day; the cross-droplet addresses (e.g. `TBHELP__STRAPI_URL`) go in part 3 of `tbapps.conf` | one stack starves the others |
| 4. Scale out | a **DO Load Balancer** (Let's Encrypt certificates on the balancer) in front of several identical droplets. The app, website and Cloud keep nothing on disk, so they copy as they are. Strapi needs its uploaded files moved to object storage (**DO Spaces**, an S3 provider in Strapi's upload settings — a change to the tbbe image) before it can run more than once | a week, with a tbbe release | a single droplet is no longer enough, or you need no downtime during updates |

Keep in mind at every step: every copy of a stack must share the same `tbapps.conf` part 4 (the same
secrets), the users' project data stays in their browsers, and backups (section 17) must cover where the
data now lives (the managed database has its own; Spaces can be versioned).

## Appendix D. Container platforms that scale by themselves

Instead of servers you look after, a container platform runs the same images and adds copies when traffic
rises — and, on some, removes them all when nobody is using it, so you pay only for requests. No Ubuntu to
patch, no `deploy.sh`, no proxy: the platform gives every address its HTTPS certificate.

| Platform | Runs | Database | Files (Strapi uploads) | Notes |
|---|---|---|---|---|
| **DigitalOcean App Platform** | images from Docker Hub | DO Managed PostgreSQL | DO Spaces | closest to Appendices A–C; same account and network |
| **Google Cloud Run** | images from Docker Hub or Artifact Registry | Cloud SQL for PostgreSQL | Cloud Storage | scales to zero; pay per request — cheapest at low traffic |
| **Azure Container Apps** | images from any registry | Azure Database for PostgreSQL | Blob Storage | scales to zero; fits organisations already on Microsoft 365 / Azure |
| **AWS App Runner** or **ECS on Fargate** | images from ECR or Docker Hub | Amazon RDS for PostgreSQL | S3 | widest choice; more to set up |
| Kubernetes (DOKS, GKE, AKS, EKS) | everything | any | any | the most control and the most work — only with a team that already runs Kubernetes |

**What carries over unchanged:** the images and their tags (`VERSION.md`), and every setting — each
stack's `.env.local` becomes that service's environment variables or secrets, still generated from
`tbapps.conf`.

**What changes:**

| Today, on one server | On a platform |
|---|---|
| containers find each other by name on `tbnet` (`tbbe:1337`, `tbhelpapp:3010`) | each service has its own HTTPS address: Cloud reaches Strapi at its public or internal address (`TBHELP__STRAPI_URL`); the app's `/ai/` route points at the AI service's address — either a small change to the tbrun image's proxy target, or the app calling the Cloud address directly (`aiBaseUrl` in `runtime-config.json`), which Cloud must then accept from the app's addresses (to be tested) |
| `runtime-config.json` is a file next to the app | the platform mounts it as a file or secret, or the tbrun image writes it from an environment variable at start (a small image change) |
| `tbpgdb`, backups with `05-backup.sh` | the managed database, with the platform's automatic backups |
| Strapi uploads in a folder | object storage (Appendix C, step 4) |
| `deploy.sh` and a tag | the platform's deploy, pinned to the same tag |
| `07-check-urls.sh` | still works: it only needs the addresses |

Platforms are often cheaper and easier at low and uneven traffic, and grow without your effort. They cost
more when traffic is steady and high, and the move itself takes careful testing. A sensible path: one
droplet now (Appendices A–B), resize while that is enough (Appendix C, step 1), then a platform once
growth makes looking after servers the bigger cost.
