# Versions

Release: **unreleased (draft)** — tested images will be pinned here when `v1.0.0` is tagged.

| Component | Image | Tag | Notes |
|---|---|---|---|
| App (offline-capable) | `jimecox807/tbrun` | `offline-v2` | reads `runtime-config.json` — one image for every customer |
| Strapi backend | `jimecox807/tbbe` | `latest` | Strapi 4.14.2; pin a digest at release |
| Website / dashboards | `jimecox807/tbwwwp` | `latest` | being reworked for run-time addresses and server-only secrets |
| Database | `postgres` | `16` | official image; seed restores into 14 or newer |
| Database admin (optional) | `dpage/pgadmin4` | `latest` | profile `tools` |
| Tunnel (optional) | `cloudflare/cloudflared` | `latest` | |

Tested on: Ubuntu 26.04 LTS, Docker Engine 29.8 from Docker's apt repository, Compose plugin (`docker compose`).
