#!/usr/bin/env bash
# 05-backup.sh — nightly backup: Strapi database (pg_dump), Strapi uploads, and this environment's settings
# (secrets.env, environment.env, each stack's .env.local, .secrets.env and .env, runtime-config.json, Caddyfile),
# and with a blog its database (tbblog.dump) and uploaded images (tbblog-uploads.tar.gz).
# Keeps KEEP_DAYS days. Copy the backup folder OFF this server too (your backup system).
#   bash scripts/05-backup.sh [environment folder] [backup folder]
# Cron (crontab -e as your admin user), every night at 02:15:
#   15 2 * * * /bin/bash <this environment folder>/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
set -euo pipefail
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"   # the environment folder this script lives in
DEST_ROOT="${2:-$HOME/backups/timebars}"
KEEP_DAYS="${KEEP_DAYS:-14}"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after scripts/01-install-docker.sh (id -nG must list docker)."; exit 1; }
set -a; . "$ROOT/postgres/.env.local"; set +a

STAMP=$(date +%Y-%m-%d_%H%M)
DEST="$DEST_ROOT/$STAMP"
mkdir -p "$DEST"; chmod 700 "$DEST_ROOT" "$DEST"

docker exec tbpgdb pg_dump -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -Fc > "$DEST/strapi.dump"
tar czf "$DEST/uploads.tar.gz" -C "$ROOT/tbbe/public" uploads
if [ -d "$ROOT/tbblog" ]; then
  BLOG_DB=$(grep -s '^DATABASE_NAME=' "$ROOT/tbblog/strapi/.env.local" | cut -d= -f2-)
  docker exec tbpgdb pg_dump -U "$POSTGRES_USER" -d "${BLOG_DB:-tbblog}" -Fc > "$DEST/tbblog.dump"
  tar czf "$DEST/tbblog-uploads.tar.gz" -C "$ROOT/tbblog" uploads
fi
tar czf "$DEST/env-files.tar.gz" -C "$ROOT" $(cd "$ROOT" && ls -d secrets.env environment.env */.env */.env.local */.secrets.env */*/.env.local */*/.secrets.env tbblog/*.env.local */runtime-config.json proxy/Caddyfile 2>/dev/null)
chmod 600 "$DEST"/*
(cd "$DEST" && sha256sum * > SHA256SUMS)

find "$DEST_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
echo "$(date -Is) backup OK: $DEST ($(du -sh "$DEST" | cut -f1))"
