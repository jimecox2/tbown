#!/usr/bin/env bash
# 00-push-to-server.sh — run on your WORKSTATION, inside your copy of this package.
#
# Copies the stack folders, the scripts and the seed data to ~/docker on the server, where Docker
# runs them. Safe to run again after you update the package: it never overwrites or deletes what
# belongs to the server (.env / .env.local files, runtime-config.json, uploaded files).
#
#   bash scripts/00-push-to-server.sh myserver          # name as in your ~/.ssh/config
set -euo pipefail
SERVER="${1:?usage: bash scripts/00-push-to-server.sh <server>   (a Host from ~/.ssh/config)}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"

command -v rsync >/dev/null || { echo "rsync is missing on this workstation (sudo apt install rsync)."; exit 1; }
ssh "$SERVER" 'command -v rsync >/dev/null' || { echo "rsync is missing on $SERVER - your server admin installs it (sudo apt install rsync)."; exit 1; }

KEEP=(--exclude '.env' --exclude '.env.local' --exclude 'runtime-config.json' --exclude 'public/uploads/***' --exclude '.gitkeep')
ssh "$SERVER" 'mkdir -p ~/docker/scripts ~/docker/seed ~/docker/tbbe/public/uploads'
rsync -rlt --itemize-changes "${KEEP[@]}" "$PKG/docker/"  "$SERVER:docker/"
rsync -rlt --itemize-changes --exclude '00-push-to-server.sh' "$PKG/scripts/" "$SERVER:docker/scripts/"
rsync -rlt --itemize-changes "$PKG/seed/"    "$SERVER:docker/seed/"
rsync -rlt --itemize-changes "$PKG/VERSION.md" "$PKG/INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md" "$SERVER:docker/"
ssh "$SERVER" 'chmod 755 ~/docker/scripts/*.sh ~/docker/*/deploy.sh ~/docker/postgres/initdb/*.sh'

echo
echo "Done: package is in ~/docker on $SERVER ($(git -C "$PKG" describe --tags --always 2>/dev/null || echo 'no git'))."
echo "Next: ssh $SERVER, and continue with the installation guide (first install: section 6)."
