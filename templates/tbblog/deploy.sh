#!/usr/bin/env bash
# deploy.sh — tbblog stack (containers tbblog-strapi and tbblog-web, each with its own tag). Same steps as every stack:
# ../scripts/deploy-common.sh. The first time, it makes the blog's database and login role on tbpgdb.
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbblog-strapi
STACK_TAGS="TBBLOG_STRAPI_TAG=jimecox807/tbblog-strapi TBBLOG_WEB_TAG=jimecox807/tbblog-web"
STACK_OLD_TAG_VAR=TBBLOG_TAG    # the single tag of earlier deploys: offered for both the first time
STACK_CONTAINER=tbblog-strapi
STACK_ENV_DIRS="strapi web"
STACK_REQUIRED="strapi/DATABASE_PASSWORD strapi/APP_KEYS strapi/API_TOKEN_SALT strapi/ADMIN_JWT_SECRET strapi/TRANSFER_TOKEN_SALT
                strapi/JWT_SECRET strapi/ENCRYPTION_KEY strapi/PUBLIC_URL web/STRAPI_URL web/BLOG_URL web/AUTH_SECRET web/REVALIDATE_SECRET"
ADMIN_IP=$(grep -s '^BLOG_ADMIN_IP=' ../environment.env | cut -d= -f2-); ADMIN_IP=${ADMIN_IP:-127.0.0.1}

val() { grep -hE "^$1=" strapi/.env.local strapi/.secrets.env | tail -1 | cut -d= -f2-; }

# The blog's own database on tbpgdb: made here the first time (the database's first-time setup only makes tbbe's).
# An existing role keeps its password: it must be the one in secrets.env (TBBLOG_DB_PASSWORD).
blog_database() {
  local db usr pw super as u
  db=$(val DATABASE_NAME); usr=$(val DATABASE_USERNAME); pw=$(val DATABASE_PASSWORD)
  [ "$db" != strapi ] || { echo "DATABASE_NAME must not be tbbe's database 'strapi' (Strapi 5 would migrate it)."; return 1; }
  super=$(grep -s '^POSTGRES_USER=' ../postgres/.env.local | cut -d= -f2-)
  as=""
  for u in "$super" postgres; do
    [ -n "$u" ] && docker exec tbpgdb psql -U "$u" -d postgres -Atc 'select 1' >/dev/null 2>&1 && { as=$u; break; }
  done
  [ -n "$as" ] || { echo "Cannot log in to tbpgdb as ${super:-?} or postgres through its local socket: docker logs tbpgdb"; return 1; }
  if [ "$(docker exec tbpgdb psql -U "$as" -d postgres -Atc "select 1 from pg_roles where rolname = '$usr'")" != 1 ]; then
    docker exec -i tbpgdb psql -v ON_ERROR_STOP=1 -U "$as" -d postgres -v usr="$usr" -v pw="$pw" >/dev/null <<'SQL' || return 1
CREATE ROLE :"usr" LOGIN PASSWORD :'pw';
SQL
    echo "  Made the database role $usr on tbpgdb."
  fi
  if [ "$(docker exec tbpgdb psql -U "$as" -d postgres -Atc "select 1 from pg_database where datname = '$db'")" != 1 ]; then
    docker exec -i tbpgdb psql -v ON_ERROR_STOP=1 -U "$as" -d postgres -v db="$db" -v usr="$usr" >/dev/null <<'SQL' || return 1
CREATE DATABASE :"db" OWNER :"usr";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
SQL
    echo "  Made the database $db on tbpgdb (empty: Strapi creates its tables on first start)."
  fi
  docker exec -e PGPASSWORD="$pw" tbpgdb psql -h 127.0.0.1 -U "$usr" -d "$db" -Atc 'select 1' >/dev/null 2>&1 || {
    echo "The role $usr on tbpgdb does not accept the password in secrets.env (TBBLOG_DB_PASSWORD)."
    echo "  Put the right one in \$TB/secrets.env and run bash ../scripts/03-make-passwords.sh, or set the role to"
    echo "  the one in secrets.env (data kept): bash ../scripts/08-reset-db-passwords.sh"
    return 1; }
  echo "  Database $db on tbpgdb accepts $usr."
}

stack_check() {
  mkdir -p uploads
  # Strapi runs as uid 1000 (node) and writes uploaded images here
  if [ "$(stat -c %u uploads)" != 1000 ]; then
    echo "Strapi (uid 1000) must own uploads:  sudo chown -R 1000:1000 uploads"
    sudo chown -R 1000:1000 uploads || return 1
  fi
  docker inspect -f '{{.State.Status}}' tbpgdb 2>/dev/null | grep -q running || { echo "Start the database first: cd ../postgres && ./deploy.sh"; return 1; }
  blog_database
}
stack_after() {
  local code s
  code=$(curl -s -o /dev/null -w '%{http_code}' http://$ADMIN_IP:1339/_health)
  [ "$code" = 204 ] && echo "  Blog Strapi /_health answers 204 (admin: http://$ADMIN_IP:1339/admin)" || echo "  WARNING: blog Strapi /_health answered $code"
  for _ in $(seq 1 20); do
    s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' tbblog-web 2>/dev/null)
    case "$s" in healthy|unhealthy|exited|dead) break ;; esac
    sleep 3
  done
  case "$s" in
    healthy|running) echo "  tbblog-web is $s" ;;
    *) echo "WARNING: tbblog-web is '${s:-missing}'. Look at: docker logs --tail 50 tbblog-web"; return 1 ;;
  esac
}

. ../scripts/deploy-common.sh
