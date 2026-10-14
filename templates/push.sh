#!/usr/bin/env bash
# push.sh — copy this environment folder from the dev box to the machine it runs on.
#   ./push.sh <server> <folder on the server>      e.g.  ./push.sh prod1 /srv/timebars/PROD
#   ./push.sh --tar                                 a .tar.gz next to this folder, to hand over another way
# <server> is a Host from ~/.ssh/config (or user@address). Run it again after you change files here:
# what belongs to the server is never overwritten - its passwords (secrets.env once it exists there, each
# stack's .secrets.env), the running tags (.env), uploaded files and backups.
set -euo pipefail
cd "$(dirname "$0")"
ENV_NAME=$(grep '^ENVIRONMENT=' environment.env | cut -d= -f2-)
SERVER_OWNED=(--exclude '.env' --exclude '.secrets.env' --exclude 'secrets.env' --exclude '.seeded' --exclude '.seeding'
              --exclude 'tbbe/public/uploads/***' --exclude 'restore-*.log' --exclude 'caddy-root.crt')

if [ "${1:-}" = --tar ]; then
  out="../${ENV_NAME}-$(date +%Y%m%d-%H%M).tar.gz"
  n=$(basename "$PWD")
  tar czf "$out" --exclude="$n/.env" --exclude="$n/*/.env" --exclude="$n/*/.secrets.env" --exclude="$n/.seeded" --exclude="$n/.seeding" \
      --exclude="$n/tbbe/public/uploads/*" --exclude="$n/restore-*.log" --exclude="$n/caddy-root.crt" -C .. "$n"
  chmod 600 "$out"
  echo "Written: $(cd .. && pwd)/$(basename "$out")"
  echo "It contains secrets.env (keys you pasted for $ENV_NAME; passwords are made on the server). Hand it over"
  echo "like a password: not by email. On the server: tar xzf $(basename "$out") && cd $(basename "$PWD") && ./deploy-all.sh"
  exit 0
fi

SERVER="${1:?usage: ./push.sh <server> <folder on the server>   or   ./push.sh --tar}"
DEST="${2:?usage: ./push.sh <server> <folder on the server>, e.g. /srv/timebars/$ENV_NAME}"
case "$DEST" in /*) ;; *) echo "The folder must be a full path starting with /"; exit 1 ;; esac
command -v rsync >/dev/null || { echo "rsync is missing on the dev box (sudo apt install rsync) - or use ./push.sh --tar"; exit 1; }
ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" true 2>/dev/null || {
  echo "Cannot ssh to $SERVER without a password. Check:  ssh $SERVER hostname   (guide: getting into a server)"; exit 1; }
ssh "$SERVER" "command -v rsync >/dev/null" || { echo "rsync is missing on $SERVER (sudo apt install rsync)."; exit 1; }
ssh "$SERVER" "mkdir -p '$DEST'" || {
  echo "Cannot create $DEST on $SERVER. If its parent belongs to root, run there once:"
  echo "  sudo mkdir -p $DEST && sudo chown \$USER: $DEST"; exit 1; }

echo "== $ENV_NAME -> $SERVER:$DEST"
rsync -rlt --itemize-changes "${SERVER_OWNED[@]}" ./ "$SERVER:$DEST/"
# secrets.env goes only the first time; from then on the server's copy (with its passwords) is the real one
rsync -rlt --ignore-existing --itemize-changes --chmod=F600 secrets.env "$SERVER:$DEST/secrets.env"
echo
echo "Done. On the server:  ssh $SERVER   then   cd $DEST && ./deploy-all.sh"
