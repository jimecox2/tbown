# Versions

The set of image tags tested together. `scripts/apply.sh` copies this file into every environment
package (`envs/<ENV>/VERSION.md`); on the server `deploy.sh` offers the tag listed here, `deploy-all.sh`
uses it without asking, and `06-health-check.sh` shows any container running a different one. After
changing a tag here, run `bash scripts/apply.sh` and push the package again. `deploy-all.sh` asks for each
app's tag as it runs (Enter takes the one it offers), so a newer image of one app needs no change here.

Release: **2026.10.09**, Timebars Container Option V2 (one package per environment from `tbapps.conf`,
see `DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md`). Every stack is deployed the same way (`.env.local` for
settings, the tag in `.env`, network `tbnet`).

| Component | Image | Tag | Notes |
|---|---|---|---|
| App | `jimecox807/tbrun` | `2026.10.09` | one image for every hostname; reads `runtime-config.json`; offline worker per host |
| Strapi backend | `jimecox807/tbbe` | `2026.10.09` | public URL, CORS origins and email sender from `.env.local` |
| Website | `jimecox807/tbwwwp` | `2026.10.09` | reads every address and key from `.env.local` at run time |
| Timebars Cloud + AI (helpapp) | `jimecox807/tbhelpapp` | `2026.10.09` | routes `/api/ai/*` need your Gemini key; checks the Timebars Cloud login |
| Blog Strapi 5 (optional, `BLOG_HOST`) | `jimecox807/tbblog-strapi` | `2026.10.24` | the blog's articles and editor accounts; own database `tbblog` on tbpgdb; admin on `BLOG_ADMIN_IP:1339` only |
| Blog (optional, `BLOG_HOST`) | `jimecox807/tbblog-web` | `2026.10.24` | Next.js 14; same tag as the blog Strapi (one `TBBLOG_TAG`) |
| Database | `postgres` | `16` | official image; the seed (made on PostgreSQL 14) restores into it |
| Database admin (optional) | `dpage/pgadmin4` | `latest` | profile `tools`; not started by `deploy.sh` |
| Proxy (`PROXY=caddy`) | `caddy` | `2.11.7-alpine` | answers every name over HTTPS; started by hand (`cd $TB/proxy && ./deploy.sh`), never by `deploy-all.sh` |

Seed: `seed/seed.dump` (Strapi database, 2.9 MB) and `seed/seed-uploads.tar.gz` (25 MB), October 2026.

Server: Ubuntu 26.04 LTS, Docker Engine 29.8.2 and Compose plugin 5.6.0 from Docker's apt repository.
