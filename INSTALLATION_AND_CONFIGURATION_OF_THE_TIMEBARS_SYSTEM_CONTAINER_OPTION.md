# Installation and Configuration of the Timebars System — Container Option

> **Draft.** This guide is being rehearsed step by step on a test server (Ubuntu 26.04, October
> 2026). Steps marked *(draft)* may still change.

## Contents

1. [What you are installing](#1-what-you-are-installing)
2. [Before you start](#2-before-you-start)
3. [Getting into the server from your workstation](#3-getting-into-the-server-from-your-workstation)
4. [Prepare the server](#4-prepare-the-server)
5. [Install Docker](#5-install-docker)
6. [Copy the stacks and create secrets](#6-copy-the-stacks-and-create-secrets)
7. [Database](#7-database)
8. [Strapi backend](#8-strapi-backend)
9. [Website and dashboards](#9-website-and-dashboards)
10. [The app](#10-the-app)
11. [Public addresses: DNS, HTTPS and the tunnel](#11-public-addresses-dns-https-and-the-tunnel)
12. [Check the installation](#12-check-the-installation)
13. [Load the seed data or a backup](#13-load-the-seed-data-or-a-backup)
14. [Backups](#14-backups)
15. [Updates and rollback](#15-updates-and-rollback)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. What you are installing

| Container | What it does | Stack folder |
|---|---|---|
| `tbpgdb` | PostgreSQL database for Strapi | `~/docker/postgres` |
| `tbbe` | Strapi backend: login, licences, publishing, registration email | `~/docker/tbbe` |
| `tbwwwp` | website, sign-up, Personal and Enterprise dashboards | `~/docker/tbwwwp` |
| `tbrun-offline` | the Agilebars / Timebars / Costbars app (works offline after first load) | `~/docker/tbrunoffline` |
| `cloudflared` | *optional* — Cloudflare Tunnel for public HTTPS addresses | `~/docker/cloudflared` |

All containers share one Docker network (`postgres_tbpg_net`) and reach each other by name. Their
ports are bound to the server itself (`127.0.0.1`) — nothing is reachable from the network until you
publish it through the tunnel or your own reverse proxy (section 11).

Project data lives in each user's browser; the server holds accounts, licences and published data.

## 2. Before you start

**Server:** Ubuntu 24.04 or 26.04 LTS, at least 2 CPU cores, 4 GB RAM, 100 GB disk, internet access
for the install (pulling images). Desktop or server edition.

**You need:**

| Item | Notes |
|---|---|
| An admin workstation on the same network | Linux or macOS terminal, or Windows with OpenSSH |
| Your hostnames | one per product you use (e.g. `pmrm.example.com`), plus the backend (`be2.example.com`) and website (`www.example.com`) |
| DNS and HTTPS | **your responsibility** — either a Cloudflare account with your domain (section 11.1), or your own DNS, reverse proxy and certificates (section 11.2) |
| Docker Hub access | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token |
| Optional services | SendGrid key (registration email), Pushover / Twilio (notifications) — see the *Administrators Guide* |

**Before the first step, someone with console access to the server:** installs Ubuntu, gives the server
a fixed address (DHCP reservation), installs `openssh-server`, and creates your admin user.

## 3. Getting into the server from your workstation

Every command in this guide runs in an SSH session from your admin workstation. Two files on the
workstation are involved, and they do different jobs:

| File | What it does | Used by |
|---|---|---|
| `/etc/hosts` | gives the server a **name** (→ its IP) | every program: ping, browser, curl, ssh |
| `~/.ssh/config` | an **SSH shortcut**: address, user, which key to use | ssh, scp, rsync only |

SSH does not need `/etc/hosts`; add both so the name also works for ping, curl and the browser.
If your organisation has DNS for the server, a DNS record replaces step 1.

```bash
# 1. a name for the server (use its real IP and name)
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

# 3. a key, copied to the server once (asks the server password once)
ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -C "$USER@$(hostname)"
ssh-copy-id -i ~/.ssh/id_ed25519.pub myserver
ssh myserver hostname        # prints the server name, no password
```

`IdentitiesOnly yes` matters: without it SSH offers every key you have, and newer OpenSSH servers
temporarily block an address after several failed attempts (*Connection reset by peer*).

Then turn off password logins on the server (keep a second session open until you have tested):
```bash
ssh -t myserver 'sudo tee /etc/ssh/sshd_config.d/10-timebars.conf >/dev/null <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo sshd -t && sudo systemctl restart ssh'
ssh myserver 'echo key login ok'
```

## 4. Prepare the server

**Your server, your policies.** You configure and maintain the server under your organisation's own
standards — hardening baseline, patching, firewall, monitoring, endpoint protection, access control.
This section lists **what the Timebars stack needs from the server** and **recommended ways** to
provide it on a standard Ubuntu LTS installation. Where your policy already covers an item, keep your
policy and check the outcome in the last column. Nothing here requires Git on the server.

| # | The stack needs | Recommended (Ubuntu) | Check |
|---|---|---|---|
| 4.1 | A patched operating system | security updates applied automatically; full updates monthly | `apt list --upgradable` is short |
| 4.2 | Correct time | NTP synchronisation, your time zone | `timedatectl` shows *synchronized: yes* |
| 4.3 | Memory headroom on a 4 GB server | a 4 GB swap file (or your standard) | `swapon --show` |
| 4.4 | No application port reachable from the network | host firewall: SSH from your admin network only | `sudo ufw status` |
| 4.5 | Key-only administrator access | section 3 (SSH keys, no passwords, no root login) | `ssh -o PubkeyAuthentication=no myserver` is refused |
| 4.6 | A few standard tools | `curl`, `ca-certificates`, `tar`, `openssl`, `python3` | `command -v curl tar openssl python3` |
| 4.7 | This package on the server | copied from your workstation (4.7 below) | `ls ~/tbown` |

Run the commands below in your SSH session (section 3). Each step stands alone; skip or replace any
step your own standards already cover.

### 4.1 Updates

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -f noninteractive unattended-upgrades     # security updates, automatically
[ -f /var/run/reboot-required ] && sudo reboot                  # only if a new kernel was installed
```
If you manage patching centrally (Landscape, Ansible, WSUS-style tooling), use that instead.

### 4.2 Time

```bash
sudo timedatectl set-timezone America/New_York     # your zone: timedatectl list-timezones
timedatectl                                         # "System clock synchronized: yes"
```
Logs, backups and scheduled jobs use this time. Point NTP at your internal time servers if your
policy requires it.

### 4.3 Swap

A 4 GB server runs the whole stack, but needs swap to absorb peaks. Skip this if the server has
8 GB or more, or already has swap.

```bash
swapon --show                                       # nothing listed = no swap yet
sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 4.4 Firewall

The containers publish their ports on the server itself only (`127.0.0.1`), so the firewall only
needs to allow SSH from your admin network. Users reach the apps through the tunnel (an outbound
connection) or your reverse proxy (section 11).

```bash
sudo apt install -y ufw
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp     # your admin network
sudo ufw enable
sudo ufw status verbose
```
Only if you run your own reverse proxy on this server (section 11.2): `sudo ufw allow 80,443/tcp`.

> **Keep the `127.0.0.1` bindings in the compose files.** Docker writes its own firewall rules, and a
> port published on all addresses (`"1337:1337"` instead of `"127.0.0.1:1337:1337"`) is reachable from
> the network **even when ufw denies it**. If you use a network firewall in front of the server, it
> needs no inbound rule except SSH (and 80/443 for your own proxy).

### 4.5 Administrator access

Done in section 3: key-only SSH, no password logins, no root login. Add your organisation's
requirements here (named accounts, MFA, session recording, sudo policy).

### 4.6 Tools

Present on a standard Ubuntu installation; install any that are missing:
```bash
sudo apt install -y curl ca-certificates tar openssl python3
```

### 4.7 Copy this package to the server

On your **workstation**, download the release archive (`tbown-<version>.tar.gz`, from the release
page or as supplied by Timebars Ltd.) and check it against the published checksum, then copy it:

```bash
sha256sum tbown-<version>.tar.gz                    # compare with the release notes
scp tbown-<version>.tar.gz myserver:~
```

On the **server**:
```bash
mkdir -p ~/tbown && tar xzf ~/tbown-<version>.tar.gz -C ~/tbown --strip-components=1
ls ~/tbown                                          # docker  scripts  seed  INSTALLATION_...md  VERSION.md
```
`~/tbown` is the unpacked package (reference copy). Section 6 copies the stack folders from it to
`~/docker`, where they run.

### 4.8 Optional: one script for the recommendations

`~/tbown/scripts/01-setup-host.sh` applies 4.1 to 4.4 and 4.6 in one go on a **fresh** server with no
local standards of its own. Read it first; do not use it where your own baseline already applies.
```bash
TZ_NAME=America/New_York SSH_FROM=192.168.1.0/24 sudo -E bash ~/tbown/scripts/01-setup-host.sh
```

## 5. Install Docker

```bash
sudo bash ~/tbown/scripts/02-install-docker.sh
exit            # log out and back in, so your user can run docker without sudo
ssh myserver
docker version && docker compose version
docker login -u <your Docker Hub user>      # paste your read-only access token
```
The script uses Docker's own repository, and Ubuntu's packages if Docker has none yet for your
release. It also turns on log rotation for every container.

## 6. Copy the stacks and create secrets

```bash
mkdir -p ~/docker && cp -rn ~/tbown/docker/* ~/docker/
bash ~/tbown/scripts/03-create-volumes.sh
bash ~/tbown/scripts/04-generate-secrets.sh ~/docker
```
`04-generate-secrets.sh` creates each `.env` from its `.env.example` with new random secrets
(never overwriting an existing one). Then fill in the values that are yours:

| File | Set |
|---|---|
| `~/docker/tbbe/.env` | `BE_URL`, `FE_URL`; `SENDGRID_API_KEY` if you use email |
| `~/docker/tbwwwp/.env` | your addresses *(draft — see section 9)* |
| `~/docker/cloudflared/.env` | `TUNNEL_TOKEN` (section 11.1) |

Keep a copy of the `.env` files in your password manager or secrets vault — they are needed to restore.

## 7. Database

```bash
cd ~/docker/postgres && docker compose up -d
docker compose ps                      # tbpgdb: healthy
docker logs tbpgdb | grep initdb       # "created role strapi and database strapi"
docker network ls | grep tbpg          # postgres_tbpg_net
```
On first start an empty database is created for Strapi, with its own login (not the superuser).

## 8. Strapi backend

```bash
cd ~/docker/tbbe
sudo chown -R 1000:1000 public/uploads
docker compose up -d && docker logs -f tbbe      # wait for "Strapi started", then Ctrl+C
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1337/_health    # 204
```
Create the first administrator at `https://<your backend address>/admin` once the public address
works (section 11), or now through an SSH tunnel: `ssh -N -L 1337:localhost:1337 myserver` and open
`http://localhost:1337/admin` on your workstation.

*(draft)* Allowed origins (CORS): the current backend image accepts the Timebars Ltd. domains and
`*.rlan.ca`; reading the list from `.env` is being added.

## 9. Website and dashboards

*(draft — the website image is being reworked to read its addresses at run time and keep every
secret on the server.)*
```bash
cd ~/docker/tbwwwp && docker compose up -d
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3001/      # 200
```

## 10. The app

One image serves every customer; your addresses go in `runtime-config.json`:
```bash
cd ~/docker/tbrunoffline
cp runtime-config.example.json runtime-config.json
nano runtime-config.json        # your backend, website and one row per app hostname
./deploy.sh                     # enter the tag from VERSION.md, e.g. v2
```
Each `sites` row maps a hostname to a product: `AB` Agilebars, `TB` Timebars, `CB` Costbars;
`"offline": true` lets that address work offline. A hostname that is not listed gets no product.

## 11. Public addresses: DNS, HTTPS and the tunnel

Choose **one** of the two ways. Either way, users reach the apps only over HTTPS (required for
offline mode).

### 11.1 Cloudflare Tunnel (no open ports)

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

### 11.2 Your own DNS, reverse proxy and certificates

See [`docker/proxy-example/README.md`](docker/proxy-example/README.md): which local address each
hostname points at, where your certificate and key go, and an example nginx configuration.
DNS records, certificates and their renewal are your responsibility.

## 12. Check the installation

```bash
bash ~/tbown/scripts/07-health-check.sh
```
Then in a browser: open each app address (the product title matches the hostname), sign in, check
*Show License*, publish a dataset and open it on the dashboard. On an app address, DevTools →
Application → Service Workers shows `sw.js` activated; tick *Offline* and press F5 — the app still loads.

## 13. Load the seed data or a backup

```bash
bash ~/tbown/scripts/05-restore-seed.sh ~/tbown/seed/seed.dump ~/tbown/seed/seed-uploads.tar.gz
```
The same script restores your own backups (section 14). It replaces the Strapi database.

## 14. Backups

```bash
bash ~/tbown/scripts/06-backup.sh            # try it once
crontab -e                                   # then schedule it nightly:
# 15 2 * * * /bin/bash $HOME/tbown/scripts/06-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```
Each backup holds the Strapi database, its uploads and the `.env` files (keep the folder private).
Copy `~/backups/timebars` off the server with your normal backup system, and practise a restore.

Users' own project data lives in their browsers: their backup files and synced spreadsheets go into
your document management system (see the *Data Synchronization, Backup, Recovery and Retention* guide).

## 15. Updates and rollback

| What | How |
|---|---|
| Ubuntu | automatic security updates; `sudo apt update && sudo apt full-upgrade` monthly |
| App | `cd ~/docker/tbrunoffline && ./deploy.sh` with the new tag; to roll back, run it with the previous tag |
| Strapi / website | set the new tag in the stack's `.env`, `docker compose pull && docker compose up -d`; back up first |
| PostgreSQL major version | backup → new `POSTGRES_TAG` with a new volume → restore |

## 16. Troubleshooting

| Symptom | Fix |
|---|---|
| `kex_exchange_identification: Connection reset by peer` | your workstation offered too many keys; use `IdentitiesOnly yes` (section 3) and wait a few minutes |
| `apt`: *Temporary failure resolving* | the server has no DNS — set gateway and DNS servers in its network settings |
| `permission denied ... docker.sock` | log out and back in after step 5 |
| Strapi cannot reach the database | `DATABASE_*` in `tbbe/.env` must match `STRAPI_DB_*` in `postgres/.env` |
| App address shows the wrong product or none | add the hostname to `runtime-config.json`, then reload twice |
| Login fails from a new address | the address is missing from Strapi's allowed origins (CORS) |
| No service worker | not HTTPS, the address lacks `"offline": true`, or `runtime-config.json` is not served |

For help, send the output of `bash ~/tbown/scripts/07-health-check.sh` and
`docker logs --tail 100 <container>` — never send `.env` files, tokens or passwords.
