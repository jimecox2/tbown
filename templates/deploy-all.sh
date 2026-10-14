#!/usr/bin/env bash
# deploy-all.sh — start or update every container of this environment, in order, with the tags in
# VERSION.md. Run it in this folder, as your admin user (no sudo), on the machine this environment runs on:
#   ./deploy-all.sh
# The first time it also makes the passwords (scripts/make-secrets.py), the Docker network and volumes, and
# loads the seed data. Safe to run again: it keeps the passwords and the data, and recreates only the
# containers whose image or settings changed. One stack on its own: cd <stack> && ./deploy.sh
set -uo pipefail
cd "$(dirname "$0")" || exit 1
die() { echo "$*" >&2; exit 1; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[ "$(id -u)" -ne 0 ] || die "Run ./deploy-all.sh WITHOUT sudo, as your admin user."
command -v docker >/dev/null || die "Docker is not installed: sudo bash scripts/install-docker.sh, then log out and in."
docker info >/dev/null 2>&1 || die "Cannot use Docker as $USER (id -nG must list docker; log out and in after scripts/install-docker.sh)."
command -v python3 >/dev/null || die "python3 is missing (sudo apt install python3)."
set -a; . ./environment.env; . postgres/.env.local; set +a
echo "Environment: $ENVIRONMENT    proxy: $PROXY    folder: $PWD"

step "Keys and passwords (secrets.env)"
python3 scripts/make-secrets.py || exit 1

step "Docker network and volumes"
docker network inspect tbnet >/dev/null 2>&1 || { docker network create tbnet >/dev/null && echo "created: network tbnet"; }
fresh=0
for v in postgres_db postgres_pgadmin; do
  if ! docker volume inspect "$v" >/dev/null 2>&1; then
    docker volume create "$v" >/dev/null && echo "created: volume $v"
    [ "$v" = postgres_db ] && fresh=1
  fi
done

export TB_AUTO=1
for s in postgres tbbe tbwww tbhelp tbrun; do
  step "$s"
  (cd "$s" && ./deploy.sh) || die "Stopped at $s - fix the message above, then run ./deploy-all.sh again."
  if [ "$s" = tbbe ]; then
    # The seed goes in once, into a new database: the volume was made just now, Strapi has no users yet,
    # or an earlier attempt stopped half way (.seeding is left behind)
    users=$(docker exec tbpgdb psql -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -Atc "select count(*) from up_users" 2>/dev/null || echo 0)
    if [ "$fresh" = 1 ] || [ -f .seeding ] || { [ ! -f .seeded ] && [ "${users:-0}" = 0 ]; }; then
      step "Seed data (first deploy)"
      touch .seeding
      bash scripts/restore.sh || die "Loading the seed failed - see above. Run ./deploy-all.sh again when fixed."
      date -Is > .seeded && rm -f .seeding
    fi
  fi
done

if [ "$PROXY" = caddy ]; then
  step "proxy (Caddy)"
  (cd proxy && ./deploy.sh) || die "Stopped at the proxy - fix the message above, then run ./deploy-all.sh again."
else
  step "proxy"
  echo "PROXY=own: no Caddy here. Your proxy sends each name to this machine - routes in proxy/Caddyfile and DEPLOY.md."
fi

step "Health check"
bash scripts/health-check.sh
echo
echo "Next: from a browser machine whose DNS (or hosts file) has these names, run  bash scripts/check-urls.sh"
grep -q '^STRAPI_ADMIN_TOKEN=.\+' secrets.env || \
  echo "Then make the Strapi API token (guide: Strapi API token), paste it in secrets.env, and run ./deploy-all.sh again."
