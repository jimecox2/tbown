# Welcome email — Container option

*Template for Timebars Ltd. Fill in the `«…»` fields, send it to the customer's technical contact,
and send the items under "Sent to you separately" by phone or another channel — never in this email.*

---

**Subject:** Your Timebars installation package — how to get started

Hello «Name»,

Thank you for choosing the Timebars container option. This email has everything you need to stand
up Agilebars, Timebars and Costbars on your own server. Keep it with the package.

## 1. What you have

| Item | Where |
|---|---|
| **Installation package** — compose files, scripts, seed data and the step-by-step guide | https://github.com/jimecox2/tbown (clone it, or download the ZIP from the green *Code* button) |
| **The guide** — follow it in order | `INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md` in the package |
| **Application images** | Docker Hub, pulled during the install once we have granted your account access (step 2 below) |
| **Seed data** — our product catalogue, website content and demo accounts | `seed/` in the package; loaded in section 14 of the guide |

Your release:

| Component | Image tag to use |
|---|---|
| App (`jimecox807/tbrun`) | `«offline-v2»` |
| Backend (`jimecox807/tbbe`) | `«latest»` |
| Website (`jimecox807/tbwwwp`) | `«tag»` |

## 2. Before you start — please do these first

1. **Docker Hub:** create a Docker Hub account (free) and a **read-only access token**
   (Account settings → Personal access tokens). **Reply to this email with your Docker Hub user
   name** — we grant it pull access and confirm.
2. **Your addresses:** choose one hostname per product and two for the backend and website, and
   **reply with them** — we confirm your backend accepts them (allowed origins). For example:

   | Purpose | Your hostname |
   |---|---|
   | Agilebars | `«agile.yourdomain»` |
   | Timebars | `«pmrm.yourdomain»` |
   | Costbars | `«ppm.yourdomain»` |
   | Backend (Strapi) | `«be2.yourdomain»` |
   | Website and dashboards | `«www.yourdomain»` |

3. **HTTPS:** decide how users will reach these addresses over HTTPS — a Cloudflare Tunnel (needs a
   Cloudflare account that manages your domain; no inbound ports) or your own DNS, reverse proxy and
   certificates. Both are described in section 12 of the guide. DNS and certificates are yours.
4. **Server:** ask your server administrator for a server that meets **section 4 of the guide**.
   In short: Ubuntu 24.04 or 26.04 LTS; at least 2 CPU cores, 4 GB RAM (with swap), 100 GB disk;
   patched and secured under your own policies; SSH key login for a **named admin user with `sudo`**
   (the scripts do not run as `root`); `curl`, `rsync`, `tar`, `openssl`, `python3` installed;
   outbound internet to Docker Hub.
5. **Workstation:** a Linux, macOS or Windows (OpenSSH) machine on the same network as the server,
   with `git` (or the ZIP) and `rsync`. You run the installation from here over SSH.

## 3. The installation in brief

The guide has the detail; this is the shape of it.

| Step | What | Guide section |
|---|---|---|
| 1 | Name the server and set up SSH keys from your workstation | 3 |
| 2 | Check the server meets the requirements | 4 |
| 3 | Send the package to the server: `bash scripts/00-push-to-server.sh <server>` | 5 |
| 4 | Install Docker, then log in to Docker Hub with your read-only token | 6 |
| 5 | Create volumes and generate secrets (on the server, never copied anywhere) | 7 |
| 6 | Start the database, then the backend | 8, 9 |
| 7 | Load the seed data | 14 |
| 8 | Start the website, then the app with your `runtime-config.json` | 10, 11 |
| 9 | Publish your HTTPS addresses (tunnel or your proxy) | 12 |
| 10 | Health check, first backup, nightly backup schedule | 13, 15 |

Plan on half a day for a first install. Everything after step 3 runs in an SSH session on the server.

## 4. Sent to you separately

By phone or another channel you choose — not by email:

- the Strapi **administrator login** contained in the seed data (change its password on first use);
- a **demo account** for the app, to check sign-in and the licence;
- confirmation that your Docker Hub account has pull access.

## 5. Who looks after what

| You | Timebars Ltd. |
|---|---|
| The server, its operating system, patching, firewall, SSH and monitoring | The application images and their updates |
| DNS, HTTPS certificates or the Cloudflare account | The installation package and guide |
| Backups off the server, and restore practice | Answers during your installation |
| Your users, licences (orders) and content in Strapi | |
| Keys for optional services: email (SendGrid), notifications (Pushover, Twilio), Google / GitHub sign-in | |

## 6. Good to know

- **Project data lives in each user's browser.** The app saves backup files automatically and syncs
  to spreadsheets; those files belong in your document management system, like any project file.
  The server holds accounts, licences and published data — the nightly backup (guide section 15)
  protects that.
- **Secrets stay on the server.** The scripts generate every password and key on the server; never
  send `.env` files to anyone, including us.
- **Email is off until you add a key.** Sign-up confirmation and password reset need an email service
  (`SENDGRID_API_KEY` in `~/docker/tbbe/.env`, or your own mail server).
- **Updates:** we announce new image tags; you pull the package update on your workstation, run
  `00-push-to-server.sh`, and redeploy as the guide's section 16 shows.

## 7. Help

If a step does not go as written, send us the output of
`bash ~/docker/scripts/06-health-check.sh` and `docker logs --tail 100 <container>` — never `.env`
files, tokens or passwords.

«Your name»
Timebars Ltd. — jcox@tbcox.com — «phone»
