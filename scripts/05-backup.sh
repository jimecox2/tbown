#!/usr/bin/env bash
# 05-backup.sh — nightly backup: Strapi database (pg_dump), Strapi uploads, and each stack's settings
# (.env.local, .env with the deployed tag, runtime-config.json).
# Keeps KEEP_DAYS days. Copy the backup folder OFF this server too (your backup system).
#   bash ~/docker/scripts/05-backup.sh [stack root] [backup folder]
# Cron (crontab -e as your admin user), every night at 02:15:
#   15 2 * * * /bin/bash $HOME/docker/scripts/05-backup.sh >> $HOME/backups/timebars/backup.log 2>&1
set -euo pipefail
ROOT="${1:-$HOME/docker}"
DEST_ROOT="${2:-$HOME/backups/timebars}"
KEEP_DAYS="${KEEP_DAYS:-14}"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
set -a; . "$ROOT/postgres/.env.local"; set +a

STAMP=$(date +%Y-%m-%d_%H%M)
DEST="$DEST_ROOT/$STAMP"
mkdir -p "$DEST"; chmod 700 "$DEST_ROOT" "$DEST"

docker exec tbpgdb pg_dump -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -Fc > "$DEST/strapi.dump"
tar czf "$DEST/uploads.tar.gz" -C "$ROOT/tbbe/public" uploads
tar czf "$DEST/env-files.tar.gz" -C "$ROOT" $(cd "$ROOT" && ls -d */.env */.env.local */runtime-config.json 2>/dev/null)
chmod 600 "$DEST"/*
(cd "$DEST" && sha256sum * > SHA256SUMS)

find "$DEST_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +"$KEEP_DAYS" -exec rm -rf {} +
echo "$(date -Is) backup OK: $DEST ($(du -sh "$DEST" | cut -f1))"
