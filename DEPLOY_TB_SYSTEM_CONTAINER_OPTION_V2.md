# Deploy the Timebars System — Container Option

One person owns the configuration setup. In VS Code, in a clone of this repo on a dev box, they fill in one file, `tbapps.conf`, with a section per environment, and run `apply` once. That makes one package per environment (`envs/DEV`, `envs/PROD` ...) with every setting already in place. Each package then goes to its own server, where a **DevOps** person starts the containers and loads the seed data with numbered scripts. Environments are deployed one at a time.

```text
 dev box: VS Code, tbown clone                          one server per environment
 tbapps.conf ── bash scripts/apply.sh ──► envs/DEV      ── 00-push-to-server.sh ──► DEV server      scripts 01..07
                                          envs/STAGING  ── 00-push-to-server.sh ──► STAGING server  scripts 01..07
                                          envs/PROD     ── 00-push-to-server.sh ──► PROD server     scripts 01..07
                                          envs/TRAINING ── 00-push-to-server.sh ──► TRAINING server scripts 01..07
```

> **Already deployed, and a release adds new settings?** Re-deploy the easy way: [15. New env variables added, how to deploy them to existing environments?](#15-new-env-variables-added-how-to-deploy-them-to-existing-environments)

Contents

- [Deploy the Timebars System — Container Option](#deploy-the-timebars-system--container-option)
  - [1. Who does what](#1-who-does-what)
  - [2. Before you start: servers, addresses and names](#2-before-you-start-servers-addresses-and-names)
  - [3. The dev box](#3-the-dev-box)
  - [4. Fill in tbapps.conf and apply it](#4-fill-in-tbappsconf-and-apply-it)
  - [5. Prepare a new server](#5-prepare-a-new-server)
  - [6. Send the package to the server](#6-send-the-package-to-the-server)
  - [7. Deploy on the server](#7-deploy-on-the-server)
  - [8. Check and finish the environment](#8-check-and-finish-the-environment)
  - [9. The next environment](#9-the-next-environment)
  - [10. Your own proxy](#10-your-own-proxy)
  - [11. Keys and passwords](#11-keys-and-passwords)
  - [12. Changes, updates and rollback](#12-changes-updates-and-rollback)
  - [13. Backups and restore](#13-backups-and-restore)
  - [14. Troubleshooting](#14-troubleshooting)
  - [15. New env variables added, how to deploy them to existing environments?](#15-new-env-variables-added-how-to-deploy-them-to-existing-environments)
  - [16. Change a key, for example a new Strapi admin token](#16-change-a-key-for-example-a-new-strapi-admin-token)

## 1. Who does what


| Who              | Does                                                                                                                       | Where                   |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| **Dev**          | fills in`tbapps.conf`, runs `apply`, checks the deployment packages, sends each one to its server                          | the dev box, in VS Code |
| **Server admin** | provides each server, patched, with an admin user and SSH key login (or runs`00-prep-new-server.sh` on a new cloud server) | each server             |
| **DNS team**     | points each environment's seven names at its server (or at your own proxy)                                                   | your DNS                |
| **DevOps**       | runs the numbered scripts on the server, tests the environment                                                             | each server, over SSH   |

One person can play several roles. The customer decides how a package reaches a server: we recommend giving the dev temporary SSH access to push it, so no secret is handed around ([section 11](#11-keys-and-passwords)).

Important: This process is simple with SSH keys, make sure you understand your orgainsations SSH key policies. These keys reside as public/private key pairs and must be securly generated and controlled by IT by giving all associated boxes the correct key.

## 2. Before you start: servers, addresses and names

Each environment runs on its own server, DEV included; environments never share a server. By Default the containers run on the same docker server. It is up to the customer to move containers to other servers and make network changes if necessary.

**Gather, per environment:** the server's IP address, and the seven names your DNS team will create. You can start without either: `apply` works with an empty IP, and the names only need to resolve before [section 8](#8-check-and-finish-the-environment).



| Item                          | Notes                                                                                                                                                                                                                                        |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Dev box**                   | any Ubuntu machine with VS Code,`git`, `python3`, `rsync` and `ssh`. It edits and sends packages. It can also be DEV's server (see [section 6](#6-send-the-package-to-the-server)); no other environment runs on it.                         |
| **A server per environment**  | Ubuntu 24.04 or 26.04, 2+ cores, 4 GB RAM (with swap), 100 GB disk, patched under your policies; an admin user with`sudo` and SSH key login; outbound internet to Docker Hub. With our Caddy proxy, ports 80 and 443 reachable by the users. |
| **Docker Hub access**         | a Docker Hub account with pull access granted by Timebars Ltd., and a read-only access token                                                                                                                                                 |
| **Seven names per environment** | Agilebars, Timebars, Costbars (one app, three names), the Strapi backend, the website, Timebars Cloud and its help library, for example`agile.prod.com`, `pmrm.prod.com`, `ppm.prod.com`, `be2.prod.com`, `www.prod.com`, `cloud.prod.com`, `help.prod.com` (you type six; the help name is made from the Cloud name) |
| **Keys (optional)**           | Google Gemini (AI), SendGrid (email), Stripe (only if you sell licences):[section 11](#11-keys-and-passwords)                                                                                                                                |

The containers in every environment:


| Container   | What it does                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------- |
| `tbpgdb`    | PostgreSQL database for Strapi                                                                                |
| `tbbe`      | Strapi backend: login, licences, publishing, registration email                                               |
| `tbwwwp`    | website: sales, sign-up, profile, orders                                                                      |
| `tbhelpapp` | Timebars Cloud (dashboards, notifications) and the AI service                                                 |
| `tbrun`     | the Agilebars / Timebars / Costbars app (works offline after the first visit)                                 |
| `tbproxy`   | Caddy: answers every name over HTTPS with Let's Encrypt certificates; not started when you use your own proxy |

Only the proxy is reachable from the network (ports 80 and 443); the other containers listen on the server itself (`127.0.0.1`).

## 3. The dev box

```bash
sudo apt install -y git python3 rsync openssh-client
git clone https://github.com/jimecox2/tbown.git ~/tbown
code ~/tbown
```

Everything on the dev box runs in VS Code's integrated terminal (*Terminal → New Terminal*), in `~/tbown`, as yourself (no sudo).

## 4. Fill in tbapps.conf and apply it

```bash
cp tbapps.conf.example tbapps.conf             # Make copy of example config file, lands in root
```

Open `tbapps.conf` in VS Code. `[ALL]` holds what every environment shares; each section below it is one environment. Delete the sections you do not need, or add one with your own name (letters only). A section may repeat any `[ALL]` setting to override it.


| Setting                                                                                   | Where                  | What                                                                                                                                                  |
| ----------------------------------------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `APP_AB_HOST`, `APP_TB_HOST`, `APP_CB_HOST`, `BACKEND_HOST`, `WEBSITE_HOST`, `CLOUD_HOST` | each section           | this environment's six names, typed in full, e.g.`pmrm.staging.com`. No two environments share a name. `CLOUD_HOST` should start with `cloud.` |
| `HELP_HOST`                                                                               | each section, optional | the help library's name. Empty = `CLOUD_HOST` with `help` for `cloud` (`cloud.prod.com` -> `help.prod.com`). It redirects to Cloud's `/help` and needs a DNS record like the others |
| `SERVER_IP`                                                                               | each section           | the server's address, for the DNS list in`DEPLOY.md`. May stay empty until you have it.                                                               |
| `PROXY`                                                                                   | each section           | `caddy` = our Caddy container on the server; `own` = your proxy ([section 10](#10-your-own-proxy))                                                    |
| `TLS`                                                                                     | each section           | `letsencrypt` = public names, ports 80/443 open to the internet; `internal` = Caddy's own certificates, for names only in internal DNS or hosts files |
| `LISTEN_IP`                                                                               | each section, optional | only with`PROXY=own` and your proxy on another machine: the server address it reaches                                                                 |
| `ACME_EMAIL`                                                                              | `[ALL]`                | Let's Encrypt sends certificate notices here                                                                                                          |
| `EMAIL_FROM`, `EMAIL_REPLY_TO`                                                            | `[ALL]`                | sender of registration and password emails (verified in SendGrid)                                                                                     |
| `APP_OFFLINE`, `EXTRA_CORS_ORIGINS`, `OP_URL`                                             | `[ALL]`                | offline mode (yes), other allowed browser origins, your OpenProject address                                                                           |
| `HELP_EDITORS`                                                                            | `[ALL]`                | emails (comma separated, no spaces) who may push content into Strapi: Cloud `/update-help`, website `/update-articles`. Each must also be an Administrator in Strapi. Empty = nobody |
| `GEMINI_API_KEY`, `SENDGRID_API_KEY`                                                      | `[ALL]`, optional      | recommended: leave empty and paste them on each server ([section 11](#11-keys-and-passwords))                                                         |

Only the section named `PROD` is open to search engines; every other environment sends `noindex`.

Then apply your edits to tbapps.conf to create envs folders.

```bash
bash scripts/apply.sh --check                  # checks the file, shows what it would make, writes nothing
bash scripts/apply.sh                          # makes envs/DEV, envs/STAGING ...
```

Each `envs/<ENV>` folder is that environment's complete package: the stack folders with their settings, `proxy/Caddyfile`, `secrets.env` (empty passwords, made later on the server), the seed data, the numbered scripts, `deploy-all.sh`, `00-push-to-server.sh` and **`DEPLOY.md`**. `DEPLOY.md` lists the environment's names and DNS records, the routes for your own proxy, and the server steps with this environment's values. Open the folders in VS Code and check them. `envs/` is never committed to git.

**Send the *Names* table of each `envs/<ENV>/DEPLOY.md` to your DNS team now**, so the records exist when you deploy. When you get an IP later, put it in `SERVER_IP` and run `bash scripts/apply.sh --force <ENV>`: before an environment's first deploy that is always safe.

`apply` runs once. After that, small changes are a find and replace in the package; [section 12](#12-changes-updates-and-rollback) has the rest.

You can make changes and re-apply by environment:  `bash scripts/apply.sh --force DEV` .

## 5. Prepare a new server

Skip this when your server admin hands you an approved server that already has an admin user with `sudo` and SSH key login, that meets organisations policies.

If you have your own Cloud VM or another box, run the prep script once as root. It patches the server, creates your admin user with `sudo`, gives it your SSH key, turns passwords off to SSH to keys only, and sets up the firewall, time sync and swap. On the dev box:

```bash
scp scripts/00-prep-new-server.sh root@<server IP>:
ssh -t root@<server IP> bash 00-prep-new-server.sh <admin user> --web --ssh-from <your IP>
```

`--web` opens ports 80 and 443 for Caddy (leave it out with `PROXY=own` and open what your proxy team asks); `--ssh-from` allows SSH only from your address (leave it out to allow SSH from anywhere). The script asks once for the admin user's password, which is for `sudo` only. At the end it prints a block for `~/.ssh/config` on the dev box; add it, for example:

Note: prod1 is the name we use for the target server.

```text
# edit the file: nano ~/.ssh/config, and enter the following for 
the target servers name and IP address.
Host prod1
    HostName 203.0.113.10
    User jcox
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
```

Keep the root session open and test from a new terminal: `ssh prod1 'hostname; sudo -v && echo sudo ok'`. If the script says a reboot is needed, run `reboot` in the root session. It is safe to run again if it stopped with an error.

## 6. Send the package to the server

On the dev box, with SSH access to the target server:
```bash
bash envs/[e.g. DEV]/00-push-to-server.sh [Host] /docker/compose
# use local for Host if installing on local box - ssh not necessary
```
The second argument is the folder where you keep Docker apps on that server (a full path, for example `/docker/compose` or `/home/<you>`); leave it out and the script asks. The package creates the folder `tbApps` inside it with scripts and seed data. It refuses a server that already holds another environment.

**Deploying Containers on same box as the tbown repo** use `local` instead of a server name, for example `bash envs/DEV/00-push-to-server.sh local /docker/compose`. It copies without SSH, so nothing asks for a password; then carry on with section 7 in the same terminal. Map the repo folders to the `$TB` variable `source ~/.bashrc` first. Test that it returns the folder path: echo `$TB`.

Run it again after any change to the package: it never overwrites what belongs to the server (its passwords, running tags, uploaded files, the seed markers).

In many organisations the Dev folks may not have access to the servers, the customer's process decides. Two other ways we recommend:


| Way                              | How                                                                                                                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| A zip file handed over by the Developer.              | `bash envs/PROD/00-push-to-server.sh --tar` creates the file: `envs/PROD-<date>.tar.gz`. Later, on the server, in the Docker apps folder: `tar xzf PROD-<date>.tar.gz`, then `echo 'export TB=$PWD/tbApps' >> ~/.bashrc`. Package extracted. |
| IT copies the folder its own way | any copy of`envs/PROD` folder in the tbown repo works; leave nothing out, and set `TB` variable to where it lands.                                                                                                                       |

## 7. Deploy on the server

Terminal into target server e.g. `ssh prod1`, then run scripts as your admin user (no sudo, except in 7.1).Look at this help file: `cat $TB/DEPLOY.md` it shows the steps and commands to run with this environment's values.

**7.1 Install Docker** (once per server), then log out and back in so your user can use Docker:

```bash
sudo bash $TB/scripts/01-install-docker.sh
```

**7.2 Log in to Docker Hub** (once per server), with your read-only access token as the password:

```bash
# jimecox807 is Timebars Ltd.'s Docker Hub account where images are pulled from.
docker login -u jimecox807
```
In the password prompt, enter the docker PAT, it may look like this: dckr_pat_xxyxyxyxyxyxyx_OmdXXX. Obtaine this from Timebars Ltd. for the right to pull images.

> **Important: re-deploying on a server where Timebars Docker volumes already exist.** If this server has run a Timebars database before, the `postgres_db` volume is still there. Postgres then skips its first-time setup and keeps the old database passwords, so Strapi stops with `password authentication failed for user "strapi"`. Check before you deploy: `docker volume ls | grep postgres`. If `postgres_db` is listed and nothing in it is needed, remove it so the environment starts clean (this deletes that database; make sure no other stack on the server uses it):
>
> ```bash
> docker rm -f tbbe tbpgdb 2>/dev/null; docker volume rm postgres_db && rm -f $TB/.seeded
> ```
>
> Then carry on with 7.3, or run `./deploy-all.sh`, which makes a new volume and loads the seed. **To keep the data instead**, set the database to the passwords in this `secrets.env`; it changes no data and restarts Strapi:
>
> ```bash
> bash $TB/scripts/08-reset-db-passwords.sh
> ```

**7.3 Create Docker network and volumes:**

```bash
bash $TB/scripts/02-create-volumes.sh
```

**7.4 Keys and passwords.** Paste this environment's keys (Gemini, SendGrid, Stripe) into `secrets.env` and leave the passwords empty. Then make the passwords: they are made here, on this server, and never leave it.

```bash
nano $TB/secrets.env
bash $TB/scripts/03-make-passwords.sh
# STRAPI_ADMIN_TOKEN can be obtained from Strapi Admin site after its up.
```

> **Experienced users: run Deploy All here.**
> With 7.1 to 7.4 done, `cd $TB && ./deploy-all.sh`
> This runs sections 7.5 to 7.9 in one go with the tags in `VERSION.md` (it repeats 7.3 and 7.4 safely). It loads the seed data only on the first deploy and is safe to run again: it keeps the passwords and the data and recreates only the containers whose image or settings changed. Then go on to [section 8](#8-check-and-finish-the-environment).

**7.5 Database and Strapi.** Each `deploy.sh` asks for the image tag; press Enter for the one in `VERSION.md`.

```bash
cd $TB/postgres && ./deploy.sh  # press enter to select defaul tag
cd $TB/tbbe && ./deploy.sh                    # waits for Strapi to start (a minute or two)
docker logs --tail 50 tbbe
```

**7.6 The seed data.** Every environment starts from the seed:

```bash
bash $TB/scripts/04-restore.sh
```

**7.7 Website, Cloud and the app:**

```bash
cd $TB/tbwww && ./deploy.sh
cd $TB/tbhelp && ./deploy.sh
cd $TB/tbrun && ./deploy.sh
```

**7.8 The proxy** (`PROXY=caddy` only; with your own proxy, see [section 10](#10-your-own-proxy)). Caddy gets a certificate for every name within a minute, once the names point at this server.

```bash
cd $TB/proxy && ./deploy.sh
```

**7.9 Health check:**

```bash
bash $TB/scripts/06-health-check.sh
```

**The Deploy All shortcut:** see the note after 7.4.

## 8. Check and finish the environment

1. **Trusted certificate (`TLS=internal` only).** Caddy signs the certificates itself, so trust its root certificate once on each browser machine, or HTTPS shows warnings and offline mode stays off. On the server: `docker cp tbproxy:/data/caddy/pki/authorities/local/root.crt ~/caddy-root.crt`, then copy that file to each browser machine. On Ubuntu: `sudo cp caddy-root.crt /usr/local/share/ca-certificates/timebars.crt && sudo update-ca-certificates`. Firefox, and Chrome on Linux: *Settings → Certificates → Authorities → Import*. Windows: double-click it → *Install* → *Trusted Root Certification Authorities*.
2. **Every name through the proxy.** Once the names resolve, run `bash $TB/scripts/07-check-urls.sh`. Every line should say OK.
3. **Strapi admin password.** The seed brings Timebars Ltd.'s admin accounts; set your own. List them with `docker exec tbpgdb psql -U strapi -d strapi -Atc "select email from admin_users"`, then run `docker exec -it tbbe strapi admin:reset-user-password` (it asks for the email and the new password).
4. **Strapi API token** (the website and Cloud need it). Open `https://<backend name>/admin` → *Settings* → *API Tokens* → **Create new API token**: name `<ENV>-server`, *Unlimited*, *Full access*. Paste it into `$TB/secrets.env` as `STRAPI_ADMIN_TOKEN=`, then run `bash $TB/scripts/03-make-passwords.sh && cd $TB && ./deploy-all.sh`.
5. **Browser check.** Open each app name (the product matches the name), sign in with a demo account, check *Show License*, publish a dataset and open it on the dashboard, and ask the help assistant a question.
6. **Nightly backup** ([section 13](#13-backups-and-restore)).

The environment is done when all of this works. Only then start the next one.

## 9. The next environment

Repeat sections 5 to 8 with the next package and its server, for example `bash envs/STAGING/00-push-to-server.sh staging1 /docker/compose`. Per environment:


|                | DEV, STAGING                   | PROD                        | TRAINING                   |
| -------------- | ------------------------------ | --------------------------- | -------------------------- |
| Stripe keys    | sandbox`sk_test_` / `pk_test_` | live`sk_live_` / `pk_live_` | sandbox, or none           |
| Search engines | kept out (`noindex`)           | indexed                     | kept out                   |
| Seed data      | loaded on the first deploy     | loaded on the first deploy  | loaded on the first deploy |

What you load into an environment after that (your own backup, a copy of PROD) is up to you: `bash $TB/scripts/04-restore.sh <dump> <uploads>` ([section 13](#13-backups-and-restore)).

## 10. Your own proxy

Set `PROXY=own` in the environment's section before `apply`. Step 7.8 is then skipped and `deploy-all.sh` starts everything except Caddy. The Caddyfile is still written (`$TB/proxy/Caddyfile`), so your proxy team can read every name and where it goes. Your proxy terminates HTTPS for each name and passes it on over HTTP, and the DNS records point at your proxy. Section *Routes* of `DEPLOY.md` has the table for that environment, for example:


| Name                | Proxy reaches           | Proxy as a container on the server, network`tbnet` |
| ------------------- | ----------------------- | -------------------------------------------------- |
| the three app names | `http://127.0.0.1:8687` | `http://tbrun:80`                                  |
| backend             | `http://127.0.0.1:1337` | `http://tbbe:1337`                                 |
| website             | `http://127.0.0.1:3001` | `http://tbwwwp:3001`                               |
| Cloud               | `http://127.0.0.1:3010` | `http://tbhelpapp:3010`                            |

Keep the `Host` header, send `X-Forwarded-Proto: https`, and do not cache `/index.html`, `/sw.js` or `/runtime-config.json`.

`127.0.0.1` only works for a proxy on the same server. When your proxy runs on another machine, set `LISTEN_IP` in the section to the server address it reaches (for example its private network address) and apply again: the containers then listen on that address and the routes table shows it. Allow only the proxy to reach those ports.

## 11. Keys and passwords


| What                                             | Made by                                               | Lives in                                                                                                      |
| ------------------------------------------------ | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Addresses, names, routes                         | `apply` on the dev box                                | each stack's`.env.local`, `tbrun/runtime-config.json`, `proxy/Caddyfile`: no secrets, safe to read and review |
| Keys: Gemini, SendGrid, Stripe, Strapi API token | pasted by whoever deploys                             | `$TB/secrets.env` on the server                                                                               |
| Database passwords and sign-in secrets           | `03-make-passwords.sh`, on the server, the first time | `$TB/secrets.env` on the server                                                                               |

**What we recommend:** leave the keys out of `tbapps.conf`. The package then holds no secret at all: the passwords are made on the server and never leave it, and the keys are pasted there. Never put a key or password in git or in an email. Keep a copy of each server's `secrets.env` in your password vault.

Where to get the keys:


| Key                                           | Where                                                                                                                                                                                                   |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GEMINI_API_KEY`                              | [aistudio.google.com](https://aistudio.google.com) → *Get API key*. Restrict it to the *Generative Language API*; add billing and a budget alert if you expect more than the free tier. Empty = AI off |
| `SENDGRID_API_KEY`                            | [SendGrid](https://www.twilio.com/en-us/sendgrid) → verify your `EMAIL_FROM` sender → *API Keys* → *Restricted Access* with *Mail Send* (starts with `SG.`). Empty = no email                        |
| `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` | [dashboard.stripe.com](https://dashboard.stripe.com) → *Developers* → *API keys* (sandbox for everything but PROD). Empty = no checkout                                                               |
| `STRAPI_ADMIN_TOKEN`                          | made after the first deploy ([section 8](#8-check-and-finish-the-environment))                                                                                                                          |

**One place for keys: `$TB/secrets.env` on the server.** Edit only that file, then send it out to the containers:

```bash
nano $TB/secrets.env
bash $TB/scripts/03-make-passwords.sh          # copies secrets.env into each stack's .secrets.env
cd $TB/tbhelp && docker compose up -d --force-recreate   # each stack that uses the key (or: cd $TB && ./deploy-all.sh)
```

Never edit a stack's `.secrets.env` (`$TB/tbwww/.secrets.env` ...): the next `03-make-passwords.sh` writes it again from `secrets.env`. `envs/<ENV>/secrets.env` on the dev box is only the starting copy for a server's first deploy: the push sends it once, and after that the server's copy is the real one, so changing it on the dev box does nothing.

Settings that are not secret (names, addresses, `HELP_EDITORS`) have one place too: `tbapps.conf` on the dev box, then `apply --force <ENV>`, push, deploy ([section 12](#12-changes-updates-and-rollback)). Never change a database password after the first deploy: the database keeps the one it was created with.

## 12. Changes, updates and rollback


| What                                       | How                                                                                                                                                                                                           |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A name or setting in one environment       | dev box: find and replace in`envs/<ENV>` (VS Code), push again (section 6), then `cd $TB && ./deploy-all.sh` on the server                                                                                    |
| A big change, or a new environment         | edit`tbapps.conf`, then `bash scripts/apply.sh` (new environments) or `bash scripts/apply.sh --force <ENV>` (makes the package again; keeps `secrets.env`; replaces your hand edits), push, `./deploy-all.sh` |
| New release                                | dev box:`git pull`, `bash scripts/apply.sh --force <ENV>` (new `VERSION.md` and scripts), push; on the server back up (`05-backup.sh`), then `cd $TB && ./deploy-all.sh`                                      |
| One container to another tag, or roll back | on the server:`cd $TB/<stack> && ./deploy.sh` and type the tag (it shows the one running now)                                                                                                                 |

## 13. Backups and restore

```bash
bash $TB/scripts/05-backup.sh                 # try it once
crontab -e                                    # then nightly, with the full path of $TB:
# 15 2 * * * /bin/bash /docker/compose/tbApps/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
```

Each backup (`~/backups/timebars/<date>`) holds the Strapi database, its uploads, `secrets.env` and the settings files. Copy that folder off the server with your normal backup system. To restore one:

```bash
bash $TB/scripts/04-restore.sh ~/backups/timebars/<date>/strapi.dump ~/backups/timebars/<date>/uploads.tar.gz
```

Users' own project data lives in their browsers; their backup files and synced spreadsheets belong in your document management system.

## 14. Troubleshooting

`bash $TB/scripts/06-health-check.sh` (inside the server) and `bash $TB/scripts/07-check-urls.sh` (through the proxy) say what is wrong in most cases.


| Symptom                                                   | Fix                                                                                                                                                                   |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `apply`: lines marked `FIX`                               | correct those lines in`tbapps.conf`; nothing was written                                                                                                              |
| `00-push-to-server.sh`: *Cannot ssh*                      | check the`Host` in `~/.ssh/config` and `ssh <server> hostname`; the key must be on the server                                                                         |
| `permission denied ... docker.sock`                       | log out and back in after`01-install-docker.sh`                                                                                                                       |
| `Pull failed`                                             | `docker login` with an account that has pull access; check the tag in `VERSION.md`                                                                                    |
| `Ports 80/443 are already in use`                         | another web server runs on this server: stop it, or set`PROXY=own`                                                                                                    |
| `07-check-urls.sh`: 000 for a name                        | the name does not point at the proxy (DNS or hosts file), ports 80/443 are closed, or (`TLS=internal`) the certificate is not trusted on this machine                 |
| `07-check-urls.sh`: 502                                   | the proxy answers but the container does not:`06-health-check.sh`, `docker logs <container>`                                                                          |
| `docker logs tbproxy`: *could not get certificate*        | Let's Encrypt cannot reach the name: public DNS record and ports 80/443 from the internet, or use`TLS=internal`                                                       |
| Login fails from a name                                   | the name is not in that environment's settings: fix it in`tbapps.conf`, `apply --force <ENV>`, push, `./deploy-all.sh`                                                |
| Strapi admin login fails                                  | the seed's admin accounts have Timebars Ltd.'s passwords: reset yours ([section 8](#8-check-and-finish-the-environment)). After 5 failed tries Strapi waits 5 minutes |
| Strapi:`password authentication failed for user "strapi"` | the `postgres_db` volume is older than this `secrets.env` (an earlier run on this server, or a new `secrets.env`): keep the data: `bash $TB/scripts/08-reset-db-passwords.sh`; or start clean: remove the volume and deploy again (the Important note before 7.3) |
| `deploy-all.sh` loads the seed again                      | it only does that for a new database volume, or after a seed load that stopped half way (`$TB/.seeding`)                                                              |
| No offline mode / no service worker                       | not HTTPS, or the certificate is not trusted (`TLS=internal`), or `APP_OFFLINE=no`                                                                                    |

For help, send the output of `bash $TB/scripts/06-health-check.sh` and `docker logs --tail 100 <container>`, never `secrets.env`, `.secrets.env` files, tokens or passwords.

## 15. New env variables added, how to deploy them to existing environments?

A new release can add settings to `tbapps.conf` (for example `HELP_EDITORS` and the help name `HELP_HOST`, October 2026). You do not delete the `envs` folders or start again: `apply --force` makes each package again from `tbapps.conf` and keeps `secrets.env`, and the push never overwrites what belongs to the server (its `secrets.env`, each stack's `.secrets.env`, the running tags in `.env`, uploads and backups).

> **`deploy-all.sh` never goes back to an older tag:** it deploys the newer of the running tag and the one in `VERSION.md`. To roll back, run `./deploy.sh` in that stack and type the tag.

**On the dev box**, in VS Code, in your tbown clone:

```bash
git pull                                       # the release: new scripts, VERSION.md, tbapps.conf.example
diff tbapps.conf.example tbapps.conf           # see which new settings the example has and your file does not
# add the new settings to tbapps.conf: [ALL] for every environment, or the [ENV] section for one
bash scripts/apply.sh --check                  # FIX lines mean a setting is missing or wrong; nothing is written
bash scripts/apply.sh --force STAGING          # once per environment: STAGING, PROD ...
bash envs/STAGING/00-push-to-server.sh <server> /docker/compose
```

If a new setting adds a name (as `HELP_HOST` did: `help.` in production, `helps.` in staging), send the new row of the *Names* table in `envs/<ENV>/DEPLOY.md` to your DNS team before you deploy.

**On the server:**

```bash
cd $TB && bash scripts/05-backup.sh            # a backup first
./deploy-all.sh                                # the VERSION.md tags; recreates only containers whose settings or image changed
# or, keeping the tags that run now (Enter at the tag question):
# cd $TB/tbwww && ./deploy.sh; cd $TB/tbhelp && ./deploy.sh; cd $TB/tbrun && ./deploy.sh; cd $TB/proxy && ./deploy.sh
bash scripts/07-check-urls.sh                  # every name answers, through the proxy
```

Then do any one-time step the release notes name. For the help release that is: give your Strapi users row `primary_role` Administrator (your email must also be in `HELP_EDITORS`), then run **Update All** on Cloud `/update-help` and, if you run tbwww, on `/update-articles`.

Repeat for the next environment. Work through staging first, then production.

## 16. Change a key, for example a new Strapi admin token

You only change one file: the `STRAPI_ADMIN_TOKEN=` line in `$TB/secrets.env`. Do this on the server (the same steps for any other key in `secrets.env`: Gemini, SendGrid, Stripe):

**1. Put the token in:**

```bash
nano $TB/secrets.env
```

The line must read `STRAPI_ADMIN_TOKEN=<new token>`, all on one line, no spaces or quotes.

**2. Check the token against Strapi** (`200` = good, `401` = the token itself is wrong). Use this environment's backend name (`BACKEND_HOST`, e.g. `be2.timebars.com`, staging `be2s.timebars.com`):

```bash
T=$(grep '^STRAPI_ADMIN_TOKEN=' $TB/secrets.env | cut -d= -f2-); curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $T" 'https://be2.timebars.com/api/help-articles?pagination[pageSize]=1'
```

**3. Copy it to the apps and restart them.** This keeps the running tags (`up -d` reads each folder's `.env` and does not pull):

```bash
bash $TB/scripts/03-make-passwords.sh
cd $TB/tbhelp && docker compose up -d --force-recreate
cd $TB/tbwww && docker compose up -d --force-recreate
```

**4. Confirm Cloud has it.** This should print `set`:

```bash
docker exec tbhelpapp sh -c 'test -n "$STRAPI_ADMIN_TOKEN" && echo set || echo empty'
```

If step 2 says `401`, make the token in this environment's own Strapi (`https://<BACKEND_HOST>/admin` → Settings → API Tokens), not another environment's, with token type **Full access**. A token made before this server's `secrets.env` was made again does not work either: a new `API_TOKEN_SALT` makes old tokens invalid. If step 4 says `empty`, check `grep -c '^STRAPI_ADMIN_TOKEN=.' $TB/tbhelp/.secrets.env` (1 = the file has it).
