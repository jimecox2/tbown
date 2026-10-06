# tbown — Timebars self-hosted package

For organisations that run the Timebars suite (Agilebars, Timebars, Costbars) on their own
servers, using the container option or the own-the-code option.

> **Status:** installation rehearsed end to end on a test server (October 2026). Release `v1.0.0`
> follows the updated website and backend images — see `VERSION.md`.

## What is in here

| Path | What it is |
|---|---|
| [`INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md`](INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md) | **Start here** — the step-by-step installation guide |
| `docker/` | one folder per stack (compose file, `.env.example`, config templates); sent to `~/docker` on the server |
| `scripts/` | `00-push-to-server.sh` (runs on your workstation) and `01`–`06` (run on the server: Docker, volumes, secrets, restore, backup, health check) |
| `seed/` | demo seed data for a first start (no real users) |
| [`VERSION.md`](VERSION.md) | the image tags this release was tested with |
| [`WELCOME_EMAIL_CONTAINER_OPTION.md`](WELCOME_EMAIL_CONTAINER_OPTION.md) | the getting-started email Timebars Ltd. sends with this package (template) |

## How it is installed

Keep this package on your **admin workstation** (clone it, or unpack a release download) and run
the installation from there:

```bash
git clone https://github.com/jimecox2/tbown.git ~/tbown && cd ~/tbown
bash scripts/00-push-to-server.sh myserver      # sends the stacks, scripts and seed to ~/docker on the server
ssh myserver                                    # every further step runs on the server, as the guide says
```

Your organisation's administrator prepares and secures the server under your own policies; the
guide states only the end state the stack needs (section 4). The scripts install Docker and the
Timebars stack. Secrets (passwords, tokens, keys) are generated on the server and never stored in
this repository or on your workstation.

## Not in here

- **The application images** — pulled from Docker Hub (`jimecox807/tbrun`, `tbbe`, `tbwwwp`).
- **Your secrets** — `.env` files are created on the server and ignored by git.
- **Decision documents** — see *Customer Ownership and Installation Options* and the
  *Administrators Guide* (in the Timebars help documentation).

Licence terms: to be published with release `v1.0.0`.
Questions: Timebars Ltd. — jcox@tbcox.com
