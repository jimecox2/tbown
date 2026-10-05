#!/usr/bin/env bash
# 02-create-volumes.sh — the named volumes the postgres stack expects (external, so that
# "docker compose down" can never delete the database). Safe to run again.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
for v in postgres_db postgres_pgadmin; do
  if docker volume inspect "$v" >/dev/null 2>&1; then echo "exists:  $v"
  else docker volume create "$v" >/dev/null && echo "created: $v"; fi
done
