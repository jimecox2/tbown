#!/bin/bash
# Runs once, when the postgres_db volume is empty: creates Strapi's own login role and database,
# so Strapi never uses the superuser. Values come from ../.env (STRAPI_DB_*).
set -euo pipefail
: "${STRAPI_DB_NAME:?}" "${STRAPI_DB_USER:?}" "${STRAPI_DB_PASSWORD:?}"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
     -v db="$STRAPI_DB_NAME" -v usr="$STRAPI_DB_USER" -v pw="$STRAPI_DB_PASSWORD" <<'SQL'
CREATE ROLE :"usr" LOGIN PASSWORD :'pw';
CREATE DATABASE :"db" OWNER :"usr";
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
SQL
echo "initdb: created role $STRAPI_DB_USER and database $STRAPI_DB_NAME"
