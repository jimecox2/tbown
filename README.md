# tbown — Timebars self-hosted package

For organisations that run the Timebars suite (Agilebars, Timebars, Costbars) on their own
servers, using the container option.

## What is in here

| Path | What it is |
|---|---|
| [`DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md`](DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md) | **Start here** — configure every environment on a dev box, deploy each with one command |
| `tbapps.conf.example` | copy to `tbapps.conf`: your domain and environments (DEV, STAGING, PROD, TRAINING) |
| `scripts/apply.sh` | makes one ready-to-deploy folder per environment in `envs/` (ignored by git) |
| `templates/` | what goes into each environment folder: stacks, proxy, `deploy-all.sh`, scripts |
| `seed/` | demo seed data, loaded on each environment's first deploy |
| [`VERSION.md`](VERSION.md) | the image tags this release was tested with |
| [`WELCOME_EMAIL_CONTAINER_OPTION.md`](WELCOME_EMAIL_CONTAINER_OPTION.md) | the getting-started email Timebars Ltd. sends with this package (template) |
| [`DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V1.md`](DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V1.md), `docker/`, `scripts_v1/` | V1: one settings file per server — kept for servers installed that way |

## How it is deployed (V2)

```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown && code ~/tbown     # on the dev box
cp tbapps.conf.example tbapps.conf                                          # fill it in
bash scripts/apply.sh                                                       # envs/DEV, envs/PROD ...
cd envs/DEV && ./deploy-all.sh                                              # DEV on the dev box
cd ../PROD && ./push.sh <server> /srv/timebars/PROD                         # then ./deploy-all.sh there
```

## Not in here

- **The application images** — pulled from Docker Hub (`jimecox807/tbrun`, `tbbe`, `tbwwwp`, `tbhelpapp`).
- **Your settings and secrets** — `tbapps.conf` and `envs/` stay on the dev box; passwords are made on each server.

Questions: Timebars Ltd. — jcox@tbcox.com
