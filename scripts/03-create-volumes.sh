#!/usr/bin/env bash
# 03-create-volumes.sh — the named volumes the postgres stack expects (external, so that
# "docker compose down" can never delete the database). Safe to run again.
set -euo pipefail
for v in postgres_db postgres_pgadmin; do
  if docker volume inspect "$v" >/dev/null 2>&1; then echo "exists:  $v"
  else docker volume create "$v" >/dev/null && echo "created: $v"; fi
done
