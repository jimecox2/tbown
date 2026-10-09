# Versions

The set of image tags tested together. `deploy.sh` offers the tag listed here, and
`06-health-check.sh` shows any container running a different one.

Release: **2026.10.09** — every stack deployed the same way (`.env.local` for settings, the tag in `.env`,
network `tbnet`).

| Component | Image | Tag | Notes |
|---|---|---|---|
| App | `jimecox807/tbrun` | `2026.10.09` | one image for every hostname; reads `runtime-config.json`; offline worker per host |
| Strapi backend | `jimecox807/tbbe` | `2026.10.09` | public URL, CORS origins and email sender from `.env.local` |
| Website | `jimecox807/tbwwwp` | `2026.10.09` | reads every address and key from `.env.local` at run time |
| Timebars Cloud + AI (helpapp) | `jimecox807/tbhelpapp` | `2026.10.09` | routes `/api/ai/*` need your Gemini key; checks the Timebars Cloud login |
| Database | `postgres` | `16` | official image; the seed (made on PostgreSQL 14) restores into it |
| Database admin (optional) | `dpage/pgadmin4` | `latest` | profile `tools`; not started by `deploy.sh` |
| Tunnel (optional) | `cloudflare/cloudflared` | `2026.10.0` | one connector per server |

Seed: `seed/seed.dump` (Strapi database, 2.9 MB) and `seed/seed-uploads.tar.gz` (25 MB), October 2026.

Server: Ubuntu 26.04 LTS, Docker Engine 29.8.2 and Compose plugin 5.6.0 from Docker's apt repository.

## Previous: rehearsal (October 2026)

`tbrun:offline-v3`, `tbbe:latest`, `tbhelpapp:v1`, `tbwwwp:rlan-test`, `postgres:16`, `cloudflared:latest`
— stack folders `tbrunoffline` and `tbwwwp`, networks `postgres_tbpg_net` and `tbhelp`.
