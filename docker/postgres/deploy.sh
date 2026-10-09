#!/usr/bin/env bash
# deploy.sh — postgres stack (container tbpgdb). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=postgres
STACK_TAG_VAR=POSTGRES_TAG
STACK_CONTAINER=tbpgdb
STACK_REQUIRED="POSTGRES_USER POSTGRES_PASSWORD STRAPI_DB_NAME STRAPI_DB_USER STRAPI_DB_PASSWORD"

# A new major version cannot read the old data files: refuse it when the volume already has a database.
stack_check_tag() {
  local ver
  ver=$(docker exec tbpgdb cat /var/lib/postgresql/data/PG_VERSION 2>/dev/null)   # empty on a first install
  if [ -n "$ver" ] && [ "${1%%.*}" != "$ver" ] && [ "${1%%-*}" != "$ver" ]; then
    echo "The database volume holds PostgreSQL $ver data; tag $1 is another major version."
    echo "Upgrade by backup and restore (05-backup.sh, new empty volume, 04-restore.sh), not by changing the tag."
    return 1
  fi
}
stack_after() { docker exec tbpgdb psql -U "$(grep '^POSTGRES_USER=' .env.local | cut -d= -f2-)" -d postgres -Atc 'select datname from pg_database where not datistemplate' | sed 's/^/  database: /'; }

. ../scripts/deploy-common.sh
