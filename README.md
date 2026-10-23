# tbown — Timebars self-hosted package

For organisations that run the Timebars suite (Agilebars, Timebars, Costbars) on their own servers, using the container option.

# git add commit push
acp "message"


## What is in here

| Path | What it is |
|---|---|
| [`DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md`](DEPLOY_TB_SYSTEM_CONTAINER_OPTION_V2.md) | **Start here**: configure every environment on a dev box, deploy each on its own server |
| `tbapps.conf.example` | copy to `tbapps.conf`: one section per environment (DEV, STAGING, PROD, TRAINING) with its six names (the help name is made from the Cloud name) |
| `scripts/apply.sh` | makes one package per environment in `envs/` (ignored by git) |
| `scripts/00-prep-new-server.sh` | readies a new cloud server: admin user, SSH keys only, firewall |
| `templates/` | what goes into each package: stacks, proxy, numbered scripts, `deploy-all.sh`, `00-push-to-server.sh` |
| `seed/` | demo seed data, loaded on each environment's first deploy |
| [`VERSION.md`](VERSION.md) | the image tags this release was tested with |
| [`WELCOME_EMAIL_CONTAINER_OPTION.md`](WELCOME_EMAIL_CONTAINER_OPTION.md) | the getting-started email Timebars Ltd. sends with this package (template) |

## How it is deployed (V2)

```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown && code ~/tbown     # dev box
cp tbapps.conf.example tbapps.conf && bash scripts/apply.sh                 # envs/DEV, envs/PROD ...
bash envs/PROD/00-push-to-server.sh prod1 /docker/compose                   # package -> server, sets $TB
ssh prod1                                                                   # then scripts 01..07, or:
cd $TB && ./deploy-all.sh
```

## Not in here

- **The application images** — pulled from Docker Hub (`jimecox807/tbrun`, `tbbe`, `tbwwwp`, `tbhelpapp`).
- **Your settings and secrets** — `tbapps.conf` and `envs/` stay on the dev box; passwords are made on each server.

Questions: Timebars Ltd. — jcox@tbcox.com
