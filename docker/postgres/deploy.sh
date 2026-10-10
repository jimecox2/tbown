#!/usr/bin/env bash
# deploy.sh — postgres stack (container tbpgdb). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=postgres
STACK_TAG_VAR=POSTGRES_TAG
STACK_CONTAINER=tbpgdb
STACK_REQUIRED="POSTGRES_USER POSTGRES_PASSWORD STRAPI_DB_NAME STRAPI_DB_USER STRAPI_DB_PASSWORD"

# A new major version cannot read the old data files: refuse it when the volume already holds a database
# of another version - a running one, or one left behind by an earlier install.
stack_check_tag() {
  local ver
  ver=$(docker exec tbpgdb cat /var/lib/postgresql/data/PG_VERSION 2>/dev/null) || \
  ver=$(docker run --rm --pull missing -v postgres_db:/d --entrypoint cat "postgres:$1" /d/PG_VERSION 2>/dev/null)
  if [ -n "$ver" ] && [ "${1%%.*}" != "$ver" ] && [ "${1%%-*}" != "$ver" ]; then
    echo "The volume postgres_db already holds a PostgreSQL $ver database; tag $1 cannot open it."
    echo "  - It is this install's data: upgrade by backup and restore (05-backup.sh, new empty volume, 04-restore.sh)."
    echo "  - It is left over from an earlier install and not needed: docker compose down; docker volume rm postgres_db;"
    echo "    bash ../scripts/02-create-volumes.sh; ./deploy.sh"
    return 1
  fi
}
stack_after() { docker exec tbpgdb psql -U "$(grep '^POSTGRES_USER=' .env.local | cut -d= -f2-)" -d postgres -Atc 'select datname from pg_database where not datistemplate' | sed 's/^/  database: /'; }

. ../scripts/deploy-common.sh
