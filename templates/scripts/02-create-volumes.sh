#!/usr/bin/env bash
# 02-create-volumes.sh — the Docker network tbnet and the database volumes, once per server.
#   bash $TB/scripts/02-create-volumes.sh
# Safe to run again: it only makes what is missing and never touches a volume that holds data.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after scripts/01-install-docker.sh (id -nG must list docker)."; exit 1; }
if docker network inspect tbnet >/dev/null 2>&1; then echo "exists:  network tbnet"; else docker network create tbnet >/dev/null && echo "created: network tbnet"; fi
for v in postgres_db postgres_pgadmin; do
  if docker volume inspect "$v" >/dev/null 2>&1; then echo "exists:  volume $v"; else docker volume create "$v" >/dev/null && echo "created: volume $v"; fi
done
