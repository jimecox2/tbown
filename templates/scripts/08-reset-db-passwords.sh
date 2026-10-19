#!/usr/bin/env bash
# 08-reset-db-passwords.sh — make the database accept the passwords in secrets.env again. Keeps all data.
#   bash $TB/scripts/08-reset-db-passwords.sh
# Use it when Strapi stops with: password authentication failed for user "strapi". That happens when the
# postgres_db volume was made with other passwords than the ones in $TB/secrets.env now (an earlier
# package on this server, a new tbApps folder, a secrets.env made again). Postgres keeps the passwords
# it was created with, so this sets the database's two login roles to the values in secrets.env, through
# the container's local socket (no password needed there), and restarts Strapi.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
bash scripts/03-make-passwords.sh >/dev/null            # each stack's .secrets.env from secrets.env
val() { grep -hE "^$1=" postgres/.env.local postgres/.secrets.env | tail -1 | cut -d= -f2-; }
SUPER=$(val POSTGRES_USER); SUPER_PW=$(val POSTGRES_PASSWORD)
APPUSER=$(val STRAPI_DB_USER); APP_PW=$(val STRAPI_DB_PASSWORD)
[ -n "$SUPER_PW" ] && [ -n "$APP_PW" ] || { echo "Passwords are empty in secrets.env: run scripts/03-make-passwords.sh"; exit 1; }

if ! docker inspect -f '{{.State.Status}}' tbpgdb 2>/dev/null | grep -q running; then
  echo "Starting the database..."; (cd postgres && docker compose up -d) >/dev/null
  for _ in $(seq 30); do docker exec tbpgdb pg_isready -q 2>/dev/null && break; sleep 2; done
fi

# The superuser of this volume: the one in .env.local, or "postgres" for a volume made another way
as=""
for u in "$SUPER" postgres; do
  if docker exec tbpgdb psql -U "$u" -d postgres -Atc 'select 1' >/dev/null 2>&1; then as=$u; break; fi
done
[ -n "$as" ] || { echo "Cannot log in to tbpgdb as $SUPER or postgres through the local socket: docker logs tbpgdb"; exit 1; }

docker exec -i tbpgdb psql -v ON_ERROR_STOP=1 -U "$as" -d postgres \
  -v su="$SUPER" -v supw="$SUPER_PW" -v usr="$APPUSER" -v pw="$APP_PW" >/dev/null <<'SQL'
SELECT format('ALTER ROLE %I PASSWORD %L', :'su', :'supw') WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'su') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'usr', :'pw') WHERE EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'usr') \gexec
SQL
missing=$(docker exec tbpgdb psql -U "$as" -d postgres -Atc "select string_agg(r, ' ') from unnest(array['$SUPER','$APPUSER']) r where r not in (select rolname from pg_roles)")
[ -z "$missing" ] || echo "WARNING: no role $missing in this database - it was not made by this package (restore a backup, or remove the volume: guide 7.3)."
echo "The database now uses the passwords in secrets.env (roles $SUPER, $APPUSER). Data unchanged."

if docker inspect tbbe >/dev/null 2>&1; then
  docker restart tbbe >/dev/null && echo "Restarted tbbe. Check: docker logs --tail 20 tbbe"
fi
