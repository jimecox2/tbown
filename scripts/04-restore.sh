#!/usr/bin/env bash
# 04-restore.sh — load a Strapi database dump (and its uploads) into this server.
# Used for the demo seed data and for restoring your own backups (05-backup.sh).
#   bash ~/docker/scripts/04-restore.sh                       (the seed: ~/docker/seed/seed.dump + seed-uploads.tar.gz)
#   bash ~/docker/scripts/04-restore.sh <dump> [uploads.tar.gz] (a backup made by 05-backup.sh)
# Replaces everything in the Strapi database. Strapi is stopped during the restore.
set -euo pipefail
ROOT="${3:-$HOME/docker}"
DUMP="${1:-$ROOT/seed/seed.dump}"
UPLOADS="${2:-}"
[ -z "$UPLOADS" ] && [ -z "${1:-}" ] && UPLOADS="$ROOT/seed/seed-uploads.tar.gz"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
set -a; . "$ROOT/postgres/.env.local"; set +a

[ -f "$DUMP" ] || { echo "No such file: $DUMP"; exit 1; }
[ "$(stat -c %s "$DUMP")" -gt 100000 ] || { echo "$DUMP is only $(stat -c %s "$DUMP") bytes - not a database dump. Make it again."; exit 1; }
head -c 5 "$DUMP" | grep -q PGDMP || { echo "$DUMP is not a pg_dump custom-format file (made with pg_dump -Fc)."; exit 1; }
if [ -f "$(dirname "$DUMP")/SHA256SUMS" ]; then (cd "$(dirname "$DUMP")" && sha256sum -c --ignore-missing SHA256SUMS); fi

echo "== Stopping Strapi"
(cd "$ROOT/tbbe" && docker compose stop)

echo "== Recreating database $STRAPI_DB_NAME"
docker exec tbpgdb psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$STRAPI_DB_NAME\" WITH (FORCE);" \
  -c "CREATE DATABASE \"$STRAPI_DB_NAME\" OWNER \"$STRAPI_DB_USER\";"

echo "== Restoring $DUMP"
LOG="$ROOT/seed/restore-$(date +%Y%m%d-%H%M).log"
set +e
docker exec -i tbpgdb pg_restore -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" \
  --no-owner --no-acl --role="$STRAPI_DB_USER" < "$DUMP" > "$LOG" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "pg_restore reported $(grep -c 'error:' "$LOG") error(s) - details in $LOG:"
  grep 'error:' "$LOG" | head -10
  echo "(Warnings about roles, owners or comments from an older PostgreSQL are usually harmless.)"
fi

if [ -n "$UPLOADS" ]; then
  echo "== Restoring uploads from $UPLOADS"
  mkdir -p "$ROOT/tbbe/public/uploads"
  tar xzf "$UPLOADS" -C "$ROOT/tbbe/public"
  sudo chown -R 1000:1000 "$ROOT/tbbe/public/uploads"
fi

# A dump made where Strapi's tables live in a schema named after the database user (e.g. "jcox")
# restores into that schema; Strapi here reads "public". Move it there when public is empty.
PSQL=(docker exec tbpgdb psql -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -Atq)
other=$("${PSQL[@]}" -c "select table_schema from information_schema.tables where table_schema not in ('public','pg_catalog','information_schema') group by 1 order by count(*) desc limit 1")
inpublic=$("${PSQL[@]}" -c "select count(*) from information_schema.tables where table_schema='public'")
if [ -n "$other" ] && [ "$inpublic" = 0 ]; then
  echo "== Tables were restored into schema '$other' - moving them to 'public'"
  "${PSQL[@]}" -c "ALTER SCHEMA public RENAME TO public_empty; ALTER SCHEMA \"$other\" RENAME TO public; DROP SCHEMA public_empty;"
fi

echo "== What is in the database now (tables with the most rows)"
docker exec tbpgdb psql -U "$POSTGRES_USER" -d "$STRAPI_DB_NAME" -q -c "ANALYZE" \
  -c "select schemaname as schema, relname as table_name, n_live_tup as rows from pg_stat_user_tables order by n_live_tup desc limit 12"

echo "== Starting Strapi"
(cd "$ROOT/tbbe" && docker compose start)
echo "Done. Watch Strapi start: docker logs -f tbbe"
