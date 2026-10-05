#!/usr/bin/env bash
# 04-restore.sh — load a Strapi database dump (and its uploads) into this server.
# Used for the demo seed data and for restoring your own backups (05-backup.sh).
#   bash ~/docker/scripts/04-restore.sh <dump file> [uploads .tar.gz] [stack root]
# Replaces everything in the Strapi database. Strapi is stopped during the restore.
set -euo pipefail
DUMP="${1:?usage: 04-restore.sh <dump> [uploads.tar.gz] [stack root]}"
UPLOADS="${2:-}"
ROOT="${3:-$HOME/docker}"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
set -a; . "$ROOT/postgres/.env"; set +a

[ -f "$DUMP" ] || { echo "No such file: $DUMP"; exit 1; }
if [ -f "$(dirname "$DUMP")/SHA256SUMS" ]; then (cd "$(dirname "$DUMP")" && sha256sum -c --ignore-missing SHA256SUMS); fi

echo "== Stopping Strapi"
(cd "$ROOT/tbbe" && docker compose stop)

echo "== Recreating database $STRAPI_DB_NAME"
docker exec tbpgdb psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$STRAPI_DB_NAME\" WITH (FORCE);" \
  -c "CREATE DATABASE \"$STRAPI_DB_NAME\" OWNER \"$STRAPI_DB_USER\";"

echo "== Restoring $DUMP"
docker exec -i tbpgdb pg_restore -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" \
  --no-owner --no-acl --role="$STRAPI_DB_USER" --exit-on-error < "$DUMP"

if [ -n "$UPLOADS" ]; then
  echo "== Restoring uploads from $UPLOADS"
  mkdir -p "$ROOT/tbbe/public/uploads"
  tar xzf "$UPLOADS" -C "$ROOT/tbbe/public"
  sudo chown -R 1000:1000 "$ROOT/tbbe/public/uploads"
fi

echo "== Starting Strapi"
(cd "$ROOT/tbbe" && docker compose start)
docker exec tbpgdb psql -U "$STRAPI_DB_USER" -d "$STRAPI_DB_NAME" -Atc \
  "select count(*) || ' tables' from information_schema.tables where table_schema='public';"
echo "Done. Watch Strapi start: docker logs -f tbbe"
