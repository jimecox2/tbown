# Versions

Release: **rehearsal (October 2026)** — `v1.0.0` follows the updated website and backend images.

Tested together on the rehearsal server:

| Component | Image | Tag | Notes |
|---|---|---|---|
| App (offline-capable) | `jimecox807/tbrun` | `offline-v3` | reads `runtime-config.json` — one image for every customer |
| Strapi backend | `jimecox807/tbbe` | `latest` | Strapi 4.14.2 on Node 16; runs on PostgreSQL 16 |
| AI service (helpapp) | `jimecox807/tbhelpapp` | `v1` | routes `/api/ai/*`; needs your Gemini key; checks the Timebars Cloud login |
| Website / dashboards | `jimecox807/tbwwwp` | `rlan-test` (rehearsal only) | release image will read its addresses at run time |
| Database | `postgres` | `16` | official image; the seed (made on PostgreSQL 14) restores into it |
| Database admin (optional) | `dpage/pgadmin4` | `latest` | profile `tools` |
| Tunnel (optional) | `cloudflare/cloudflared` | `latest` | |

Seed: `seed/seed.dump` (Strapi database, 2.9 MB) and `seed/seed-uploads.tar.gz` (25 MB), October 2026.

Server: Ubuntu 26.04 LTS, Docker Engine 29.8.2 and Compose plugin 5.6.0 from Docker's apt repository.
