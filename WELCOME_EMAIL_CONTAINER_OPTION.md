# Welcome email — Container option

*Template for Timebars Ltd. Fill in the `«…»` fields, send it to the customer's technical contact,
and send the items under "Sent to you separately" by phone or another channel — never in this email.*

---

**Subject:** Your Timebars installation package — how to get started

Hello «Name»,

Thank you for choosing the Timebars container option. This email has what you need to stand up
Agilebars, Timebars and Costbars in your own environments (for example DEV, STAGING, PROD and TRAINING).

## 1. What you have

| Item | Where |
|---|---|
| **Installation package** — scripts, seed data and the guide | https://github.com/jimecox2/tbown |
| **The guide** — follow it in order | `DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md` in the package |
| **Application images** | Docker Hub, once we have granted your account access (step 2 below) |

Your release: **«package release, e.g. v2.0.0»**. The image tags are in `VERSION.md`.

## 2. Before you start

1. **Docker Hub:** create a Docker Hub account and a **read-only access token**, and **reply with your
   Docker Hub user name** — we grant it pull access.
2. **A dev box:** an Ubuntu 24.04 or 26.04 machine with VS Code, 8 GB RAM and 100 GB disk. Your developer
   configures every environment there and runs DEV on it.
3. **A server per other environment:** Ubuntu 24.04 or 26.04, 2+ cores, 4 GB RAM, 100 GB disk, patched under
   your policies, an admin user with `sudo` and SSH key login (guide section 1).
4. **Names:** the guide makes six names per environment from your domain (e.g. `pmrm.example.com`,
   `pmrms.example.com` for staging) and lists them for your DNS team. HTTPS comes from our proxy
   container with free Let's Encrypt certificates, or from **your own proxy** — the guide gives its routes.
   **Reply with your domain** so we confirm your names.

## 3. The installation in brief

| Step | What | Guide section |
|---|---|---|
| 1 | Clone the package on the dev box, open it in VS Code | 2 |
| 2 | Fill in `tbapps.conf` (domain, environments), run `bash scripts/apply.sh` | 3 |
| 3 | Send each environment's name list to your DNS team | 3 |
| 4 | Deploy DEV on the dev box: `cd envs/DEV && ./deploy-all.sh`, and test it | 4, 5 |
| 5 | Copy each other environment to its server, run `./deploy-all.sh` there | 6 |

Plan on half a day for DEV, and an hour for each further environment once its names point at it.

## 4. Sent to you separately

By phone or another channel you choose — not by email:

- the Strapi **administrator login** contained in the seed data (change its password on first use);
- a **demo account** for the app, to check sign-in and the licence;
- confirmation that your Docker Hub account has pull access.

## 5. Who looks after what

| You | Timebars Ltd. |
|---|---|
| The dev box and servers, their operating system, patching, firewall, SSH and monitoring | The application images and their updates |
| DNS, and your own proxy if you use one | The installation package and guide |
| Backups off the servers, and restore practice | Answers during your installation |
| Your users, licences (orders) and content in Strapi | |
| Keys for optional services: Gemini (AI), SendGrid (email), Stripe (payments) | |

## 6. Good to know

- **Project data lives in each user's browser.** The app saves backup files and syncs to spreadsheets; those
  files belong in your document management system. The servers hold accounts, licences and published data
  — the nightly backup (guide section 10) protects that.
- **Passwords are made on each server** the first time it is deployed, and never leave it. The folder your
  developer hands over holds no password. Never send `secrets.env` files to anyone, including us.
- **Updates:** we announce new image tags; your developer pulls the package update, makes the environment
  folders again and redeploys (guide section 9).

## 7. Help

If a step does not go as written, send us the output of `bash scripts/health-check.sh` and
`docker logs --tail 100 <container>` — never `secrets.env` files, tokens or passwords.

«Your name»
Timebars Ltd. — jcox@tbcox.com — «phone»
