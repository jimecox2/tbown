#!/usr/bin/env bash
# 02-create-volumes.sh — the named volumes the postgres stack expects (external, so that
# "docker compose down" can never delete the database), and the Docker network tbnet that every
# Timebars container joins (containers find each other by name). Safe to run again.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
for v in postgres_db postgres_pgadmin; do
  if docker volume inspect "$v" >/dev/null 2>&1; then echo "exists:  $v"
  else docker volume create "$v" >/dev/null && echo "created: $v"; fi
done
# An existing postgres_db may hold a database from an earlier install (perhaps another PostgreSQL version).
tag=$(awk -F'|' '$3 ~ /`postgres`/ {gsub(/[ `]/,"",$4); print $4; exit}' "$(dirname "$0")/../VERSION.md" 2>/dev/null)
ver=$(docker run --rm --pull missing -v postgres_db:/d --entrypoint cat "postgres:${tag:-16}" /d/PG_VERSION 2>/dev/null || true)
if [ -n "$ver" ]; then
  echo "note:    postgres_db already holds a PostgreSQL $ver database. Keep it only if it is this install's data."
  echo "         Left over from an earlier install? Remove it before the first deploy: docker volume rm postgres_db"
  echo "         (then run this script again)."
fi
if docker network inspect tbnet >/dev/null 2>&1; then echo "exists:  network tbnet"
else docker network create tbnet >/dev/null && echo "created: network tbnet"; fi
