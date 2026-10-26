#!/usr/bin/env bash
# deploy-all.sh — the shortcut: every step of the guide's server part in one go, with the tags in VERSION.md.
# On the server, as your admin user (no sudo), after 01-install-docker.sh and docker login:
#   cd $TB && ./deploy-all.sh
# It runs 02-create-volumes.sh, 03-make-passwords.sh, ./deploy.sh in postgres, tbbe, then 04-restore.sh (the
# seed data, first deploy only), ./deploy.sh in tbwww, tbhelp, tbrun and tbblog (only with a blog), and
# 06-health-check.sh. It never starts the proxy: with PROXY=caddy run  cd $TB/proxy && ./deploy.sh  yourself. Safe to run again: it keeps the passwords and the data, and recreates only the
# containers whose image or settings changed. The same steps one by one: the guide, or DEPLOY.md.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
die() { echo "$*" >&2; exit 1; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

[ "$(id -u)" -ne 0 ] || die "Run ./deploy-all.sh WITHOUT sudo, as your admin user."
command -v docker >/dev/null || die "Docker is not installed: sudo bash scripts/01-install-docker.sh, then log out and in."
docker info >/dev/null 2>&1 || die "Cannot use Docker as $USER (id -nG must list docker; log out and in after scripts/01-install-docker.sh)."
command -v python3 >/dev/null || die "python3 is missing (sudo apt install python3)."
set -a; . ./environment.env; . postgres/.env.local; set +a
echo "Environment: $ENVIRONMENT    proxy: $PROXY    folder: $PWD"

step "Network and volumes (02-create-volumes.sh)"
fresh=0
docker volume inspect postgres_db >/dev/null 2>&1 || fresh=1
bash scripts/02-create-volumes.sh || exit 1

step "Passwords (03-make-passwords.sh)"
bash scripts/03-make-passwords.sh || exit 1

export TB_AUTO=1
stacks="postgres tbbe tbwww tbhelp tbrun"
[ -d tbblog ] && stacks="$stacks tbblog"     # the blog: only in environments with BLOG_HOST
for s in $stacks; do
  step "$s"
  (cd "$s" && ./deploy.sh) || die "Stopped at $s - fix the message above, then run ./deploy-all.sh again."
  if [ "$s" = tbbe ]; then
    # The seed goes in once, into a new database: the volume was made just now, Strapi has no users yet,
    # or an earlier attempt stopped half way (.seeding is left behind)
    users=$(docker exec tbpgdb psql -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -Atc "select count(*) from up_users" 2>/dev/null || echo 0)
    if [ "$fresh" = 1 ] || [ -f .seeding ] || { [ ! -f .seeded ] && [ "${users:-0}" = 0 ]; }; then
      step "Seed data, first deploy (04-restore.sh)"
      bash scripts/04-restore.sh || die "Loading the seed failed - see above. Run ./deploy-all.sh again when fixed."
    fi
  fi
done

step "proxy"
if [ "$PROXY" = caddy ]; then
  echo "Not started here. To start or update Caddy (certificates for every name):  cd $PWD/proxy && ./deploy.sh"
else
  echo "PROXY=own: no Caddy here. Your proxy sends each name to this machine - routes in proxy/Caddyfile and DEPLOY.md."
fi

step "Health check (06-health-check.sh)"
bash scripts/06-health-check.sh
echo
echo "Next: from a browser machine whose DNS (or hosts file) has these names, run  bash scripts/07-check-urls.sh"
grep -q '^STRAPI_ADMIN_TOKEN=.\+' secrets.env || \
  echo "Then make the Strapi API token (guide: Strapi API token), paste it in secrets.env, and run ./deploy-all.sh again."
true
