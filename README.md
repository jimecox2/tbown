# tbown — Timebars self-hosted package

For organisations that run the Timebars suite (Agilebars, Timebars, Costbars) on their own
servers, using the container option or the own-the-code option.

> **Status:** first release in preparation (October 2026). The installation is being rehearsed on a
> test server; until release `v1.0.0` is tagged, treat everything here as a draft.

## What is in here

| Path | What it is |
|---|---|
| [`INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md`](INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md) | **Start here** — the step-by-step installation guide |
| `docker/` | one folder per stack (compose file, `.env.example`, config templates); copied to `~/docker` on the server |
| `scripts/` | numbered helper scripts used by the guide (host setup, Docker, secrets, restore, backup, health check) |
| `seed/` | demo seed data for a first start (no real users) |
| [`VERSION.md`](VERSION.md) | the image tags this release was tested with |

## How you get it onto your server

Your organisation configures and maintains the server under its own policies; the guide lists what
the stack needs and the recommended way to provide it.

Download the release archive on your admin workstation, check its checksum, copy it to the server
with `scp` and unpack it there (installation guide, section 4.7). No Git is needed on the server.

Everything you need to know is in the installation guide. Secrets (passwords, tokens, keys) are
generated on your server and never stored in this repository.

## Not in here

- **The application images** — pulled from Docker Hub (`jimecox807/tbrun`, `tbbe`, `tbwwwp`).
- **Your secrets** — `.env` files are created on the server and ignored by git.
- **Decision documents** — see *Customer Ownership and Installation Options* and the
  *Administrators Guide* (in the Timebars help documentation).

Licence terms: to be published with release `v1.0.0`.
Questions: Timebars Ltd. — jcox@tbcox.com
