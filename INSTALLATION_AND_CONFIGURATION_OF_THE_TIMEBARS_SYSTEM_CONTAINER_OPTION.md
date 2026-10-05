# Installation and Configuration of the Timebars System — Container Option

> **Draft.** This guide is being rehearsed step by step on a test server (Ubuntu 26.04, October
> 2026). Steps marked *(draft)* may still change.

## Contents

1. [What you are installing](#1-what-you-are-installing)
2. [How the installation works](#2-how-the-installation-works)
3. [Getting into the server from your workstation](#3-getting-into-the-server-from-your-workstation)
4. [Server requirements (your administrator)](#4-server-requirements-your-administrator)
5. [Send the package to the server](#5-send-the-package-to-the-server)
6. [Install Docker](#6-install-docker)
7. [Volumes and secrets](#7-volumes-and-secrets)
8. [Database](#8-database)
9. [Strapi backend](#9-strapi-backend)
10. [Website and dashboards](#10-website-and-dashboards)
11. [The app](#11-the-app)
12. [Public addresses: DNS, HTTPS and the tunnel](#12-public-addresses-dns-https-and-the-tunnel)
13. [Check the installation](#13-check-the-installation)
14. [Load the seed data or a backup](#14-load-the-seed-data-or-a-backup)
15. [Backups](#15-backups)
16. [Updates and rollback](#16-updates-and-rollback)
17. [Troubleshooting](#17-troubleshooting)

---

## 1. What you are installing

| Container | What it does | Folder on the server |
|---|---|---|
| `tbpgdb` | PostgreSQL database for Strapi | `~/docker/postgres` |
| `tbbe` | Strapi backend: login, licences, publishing, registration email | `~/docker/tbbe` |
| `tbwwwp` | website, sign-up, Personal and Enterprise dashboards | `~/docker/tbwwwp` |
| `tbrun-offline` | the Agilebars / Timebars / Costbars app (works offline after first load) | `~/docker/tbrunoffline` |
| `cloudflared` | *optional* — Cloudflare Tunnel for public HTTPS addresses | `~/docker/cloudflared` |

All containers share one Docker network (`postgres_tbpg_net`) and reach each other by name. Their
ports are bound to the server itself (`127.0.0.1`) — nothing is reachable from the network until you
publish it through the tunnel or your own reverse proxy (section 12).

Project data lives in each user's browser; the server holds accounts, licences and published data.

## 2. How the installation works

| Who | Where | Does what |
|---|---|---|
| **Your server administrator** | the server | provides a server that meets section 4, under your organisation's own policies (patching, firewall, SSH, hardening) |
| **You (installer)** | your admin workstation | keeps this package (clone or release download), sends it to the server with one command (section 5), and runs every other step from an SSH session |
| **The scripts in this package** | the server | install Docker and the Timebars stack, generate secrets, back up and restore |

```text
 workstation                                   server
 ~/tbown  (this package, your copy)            ~/docker/postgres  tbbe  tbwwwp  tbrunoffline  cloudflared
   docker/   scripts/   seed/      ── 00-push-to-server.sh ──►   ~/docker/scripts/   ~/docker/seed/
                                               ~/docker/*/.env   ← created ON the server, never copied back
```

The stack folders must be on the server because Docker runs there and reads them locally. Secrets
are generated on the server and never leave it — not to your workstation, not into Git.

**What you need before you start**

| Item | Notes |
|---|---|
| Admin workstation on the same network | Linux, macOS, or Windows with OpenSSH; `git` or a release download of this package; `rsync` |
| Your hostnames | one per product you use (e.g. `pmrm.example.com`), plus the backend (`be2.example.com`) and website (`www.example.com`) |
| DNS and HTTPS | **your responsibility** — a Cloudflare account with your domain (section 12.1), or your own DNS, reverse proxy and certificates (section 12.2) |
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
| 4.6 | Host firewall: inbound SSH from the admin network only (plus 80/443 only if you run your own proxy on this server, section 12.2) | `ssh -t myserver sudo ufw status` (or your firewall's equivalent) |
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

## 7. Volumes and secrets

```bash
bash ~/docker/scripts/02-create-volumes.sh
bash ~/docker/scripts/03-generate-secrets.sh
```
`03-generate-secrets.sh` creates each stack's `.env` from its `.env.example` with new random secrets
(`chmod 600`, never overwriting an existing one). Then fill in the values that are yours:

| File (on the server) | Set |
|---|---|
| `~/docker/tbbe/.env` | `BE_URL`, `FE_URL`; `SENDGRID_API_KEY` if you use email |
| `~/docker/tbwwwp/.env` | your addresses *(draft — see section 10)* |
| `~/docker/cloudflared/.env` | `TUNNEL_TOKEN` (section 12.1) |

```bash
nano ~/docker/tbbe/.env
```
Store a copy of the `.env` files in your password manager or secrets vault — a restore needs them.

## 8. Database

```bash
cd ~/docker/postgres && docker compose up -d
docker compose ps                      # tbpgdb: healthy
docker logs tbpgdb | grep initdb       # "created role strapi and database strapi"
docker network ls | grep tbpg          # postgres_tbpg_net
```
On first start an empty database is created for Strapi, with its own login (not the superuser).

## 9. Strapi backend

```bash
cd ~/docker/tbbe
sudo chown -R 1000:1000 public/uploads
docker compose up -d && docker logs -f tbbe      # wait for "Strapi started", then Ctrl+C
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1337/_health    # 204
```
Create the first administrator at `https://<your backend address>/admin` once the public address
works (section 12), or now through an SSH tunnel from your workstation:
`ssh -N -L 1337:localhost:1337 myserver`, then open `http://localhost:1337/admin`.

*(draft)* Allowed origins (CORS): the current backend image accepts the Timebars Ltd. domains and
`*.rlan.ca`; reading the list from `.env` is being added.

## 10. Website and dashboards

*(draft — the website image is being reworked to read its addresses at run time and keep every
secret on the server.)*
```bash
cd ~/docker/tbwwwp && docker compose up -d
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3001/      # 200
```

## 11. The app

One image serves every customer; your addresses go in `runtime-config.json`:
```bash
cd ~/docker/tbrunoffline
cp runtime-config.example.json runtime-config.json
nano runtime-config.json        # your backend, website and one row per app hostname
./deploy.sh                     # enter the tag from VERSION.md, e.g. v2
```
Each `sites` row maps a hostname to a product: `AB` Agilebars, `TB` Timebars, `CB` Costbars;
`"offline": true` lets that address work offline. A hostname that is not listed gets no product.

## 12. Public addresses: DNS, HTTPS and the tunnel

Choose **one** of the two ways. Either way, users reach the apps only over HTTPS (required for
offline mode).

### 12.1 Cloudflare Tunnel (no open ports)

1. In Cloudflare Zero Trust → Networks → Tunnels, create a tunnel and copy its token into
   `~/docker/cloudflared/.env` (`TUNNEL_TOKEN=...`).
2. Start it: `cd ~/docker/cloudflared && docker compose up -d && docker logs cloudflared` — the
   tunnel shows *Healthy* in the dashboard.
3. Add one *published application* per hostname, pointing at the container by name:

| Hostname (example) | Service |
|---|---|
| `agile.example.com`, `pmrm.example.com`, `ppm.example.com` | `http://tbrun-offline:80` |
| `be2.example.com` | `http://tbbe:1337` |
| `www.example.com` | `http://tbwwwp:3001` |

Keep *Rocket Loader* off and do not add *Cache Everything* rules for these hostnames.

### 12.2 Your own DNS, reverse proxy and certificates

See [`docker/proxy-example/README.md`](docker/proxy-example/README.md): which local address each
hostname points at, where your certificate and key go, and an example nginx configuration.
DNS records, certificates and their renewal are your responsibility.

## 13. Check the installation

```bash
bash ~/docker/scripts/06-health-check.sh
```
Then in a browser: open each app address (the product title matches the hostname), sign in, check
*Show License*, publish a dataset and open it on the dashboard. On an app address, DevTools →
Application → Service Workers shows `sw.js` activated; tick *Offline* and press F5 — the app still loads.

## 14. Load the seed data or a backup

```bash
bash ~/docker/scripts/04-restore.sh ~/docker/seed/seed.dump ~/docker/seed/seed-uploads.tar.gz
```
The same script restores your own backups (section 15). It replaces the Strapi database.

## 15. Backups

```bash
bash ~/docker/scripts/05-backup.sh           # try it once
crontab -e                                   # then schedule it nightly:
# 15 2 * * * /bin/bash $HOME/docker/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup holds the Strapi database, its uploads and the `.env` files (the folder is private to your
admin user). Copy `~/backups/timebars` off the server with your normal backup system, and practise a
restore.

Users' own project data lives in their browsers: their backup files and synced spreadsheets go into
your document management system (see the *Data Synchronization, Backup, Recovery and Retention* guide).

## 16. Updates and rollback

| What | How |
|---|---|
| This package | workstation: `git pull` (or new release), then `bash scripts/00-push-to-server.sh myserver` |
| App | server: `cd ~/docker/tbrunoffline && ./deploy.sh` with the new tag; roll back with the previous tag |
| Strapi / website | set the new tag in the stack's `.env`, `docker compose pull && docker compose up -d`; back up first |
| PostgreSQL major version | backup → new `POSTGRES_TAG` with a new volume → restore |
| Ubuntu, firewall, SSH | your administrator, under your policies |

## 17. Troubleshooting

| Symptom | Fix |
|---|---|
| `kex_exchange_identification: Connection reset by peer` | your workstation offered too many keys; use `IdentitiesOnly yes` (section 3) and wait a few minutes |
| `00-push-to-server.sh`: *rsync is missing* | install `rsync` on the workstation or ask the administrator to install it on the server (section 4.7) |
| `apt`: *Temporary failure resolving* | the server has no DNS — your administrator sets gateway and DNS servers |
| `permission denied ... docker.sock` | log out and back in after section 6 |
| Docker install says *Cannot reach download.docker.com* | the server has no internet access to Docker (proxy, firewall); fix it and run the script again |
| Strapi cannot reach the database | `DATABASE_*` in `tbbe/.env` must match `STRAPI_DB_*` in `postgres/.env` |
| App address shows the wrong product or none | add the hostname to `runtime-config.json`, then reload twice |
| Login fails from a new address | the address is missing from Strapi's allowed origins (CORS) |
| No service worker | not HTTPS, the address lacks `"offline": true`, or `runtime-config.json` is not served |

For help, send the output of `bash ~/docker/scripts/06-health-check.sh` and
`docker logs --tail 100 <container>` — never send `.env` files, tokens or passwords.
