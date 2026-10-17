#!/usr/bin/env bash
# 00-push-to-server.sh — on the dev box, copy this environment's package to its server.
#
#   bash envs/PROD/00-push-to-server.sh prod1                    # asks where you keep Docker apps there
#   bash envs/PROD/00-push-to-server.sh prod1 /docker/compose    # -> /docker/compose/tbApps
#   bash envs/DEV/00-push-to-server.sh local /docker/compose     # this machine itself (no ssh)
#   bash envs/PROD/00-push-to-server.sh --tar                    # a .tar.gz to hand over another way
#
# <server> is a Host from ~/.ssh/config (or user@address), or local for the machine you are on. The package goes into a folder tbApps inside the
# parent folder you give (a FULL path, e.g. /docker/compose or /home/<you>); your answer is remembered in
# this folder (.push-target, not in git). It also sets TB=<parent>/tbApps in the server user's ~/.bashrc, so
# the guide's commands (cd $TB/tbbe && ./deploy.sh) work as written.
# Safe to run again after you change files here: what belongs to the server is never overwritten - its
# passwords (secrets.env once it exists there, each stack's .secrets.env), the running tags (.env), the seed
# markers, uploaded files and backups.
set -euo pipefail
cd "$(dirname "$0")"
ENV_NAME=$(grep '^ENVIRONMENT=' environment.env | cut -d= -f2-)
SERVER_OWNED=(--exclude '.env' --exclude '.secrets.env' --exclude 'secrets.env' --exclude '.seeded' --exclude '.seeding'
              --exclude 'tbbe/public/uploads/***' --exclude 'restore-*.log' --exclude 'caddy-root.crt'
              --exclude '00-push-to-server.sh' --exclude '.push-target' --exclude '__pycache__')

if [ "${1:-}" = --tar ]; then
  out="../${ENV_NAME}-$(date +%Y%m%d-%H%M).tar.gz"
  n=$(basename "$PWD")
  tar czf "$out" --transform "s#^$n#tbApps#" --exclude="$n/.env" --exclude="$n/*/.env" --exclude="$n/*/.secrets.env" \
      --exclude="$n/.seeded" --exclude="$n/.seeding" --exclude="$n/tbbe/public/uploads/*" --exclude="$n/restore-*.log" \
      --exclude="$n/caddy-root.crt" --exclude="$n/00-push-to-server.sh" --exclude="$n/.push-target" --exclude='__pycache__' -C .. "$n"
  chmod 600 "$out"
  echo "Written: $(cd .. && pwd)/$(basename "$out")"
  echo "It holds secrets.env (any keys you pasted for $ENV_NAME; passwords are made on the server). Hand it over"
  echo "like a password: not by email. On the server, in the parent folder: tar xzf $(basename "$out")"
  echo "then:  echo 'export TB=\$PWD/tbApps' >> ~/.bashrc && . ~/.bashrc"
  exit 0
fi

SERVER="${1:?usage: bash envs/$ENV_NAME/00-push-to-server.sh <server|local> [parent folder]   or   --tar}"
if [ "$SERVER" = local ]; then
  run() { bash -c "$1"; }; DEST=""
else
  run() { ssh "$SERVER" "$1"; }; DEST="$SERVER:"
fi
command -v rsync >/dev/null || { echo "rsync is missing on the dev box (sudo apt install rsync) - or use --tar"; exit 1; }
if [ "$SERVER" != local ]; then
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$SERVER" true 2>/dev/null || {
    echo "Cannot ssh to $SERVER without a password. Check:  ssh $SERVER hostname   (guide: getting into the server)"
    echo "If $SERVER is this machine itself, use:  bash envs/$ENV_NAME/00-push-to-server.sh local <parent folder>"; exit 1; }
  ssh "$SERVER" "command -v rsync >/dev/null" || { echo "rsync is missing on $SERVER (sudo apt install rsync)."; exit 1; }
fi

# --- where on the server ---------------------------------------------------------------------------
PARENT="${2:-}"
if [ -z "$PARENT" ]; then
  last=$(cat .push-target 2>/dev/null || true)
  echo "Where do you keep Docker apps on $SERVER? Give the FULL path of that folder, starting with /"
  echo "(for example /docker/compose or /home/<you>). A folder tbApps is created inside it for $ENV_NAME."
  read -r -p "Parent folder${last:+ (press Enter for $last)}: " PARENT
  PARENT=${PARENT:-$last}
fi
PARENT=${PARENT%/}
case "$PARENT" in /*) ;; *) echo "'$PARENT' is not a full path: it must start with /"; exit 1 ;; esac
case "$PARENT" in *[[:space:]]*) echo "The path must not contain spaces."; exit 1 ;; esac
run "[ -d '$PARENT' ]" || { echo "$PARENT does not exist on $SERVER - create it first, or check the spelling."; exit 1; }
ROOT="$PARENT/tbApps"
[ "${PARENT##*/}" = tbApps ] && ROOT="$PARENT"
other=$(run "grep -s '^ENVIRONMENT=' '$ROOT/environment.env' | cut -d= -f2-" || true)
[ -z "$other" ] || [ "$other" = "$ENV_NAME" ] || {
  echo "$ROOT on $SERVER holds the $other environment. One environment per server: pick the right server."; exit 1; }
run "mkdir -p '$ROOT'" || {
  echo "Cannot create $ROOT on $SERVER. If $PARENT belongs to root, run there once:"
  echo "  sudo mkdir -p $ROOT && sudo chown \$USER: $ROOT"; exit 1; }
echo "$PARENT" > .push-target

# --- copy ------------------------------------------------------------------------------------------
echo "== $ENV_NAME -> ${DEST:-this machine: }$ROOT"
rsync -rlt --itemize-changes "${SERVER_OWNED[@]}" ./ "$DEST$ROOT/"
# secrets.env goes only the first time; from then on the server's copy (with its passwords) is the real one
rsync -rlt --ignore-existing --itemize-changes --chmod=F600 secrets.env "$DEST$ROOT/secrets.env"

# --- TB in the server user's ~/.bashrc --------------------------------------------------------------
run "touch ~/.bashrc; if grep -q '^export TB=' ~/.bashrc; then sed -i 's#^export TB=.*#export TB=$ROOT    \# Timebars $ENV_NAME (tbown)#' ~/.bashrc; else echo 'export TB=$ROOT    # Timebars $ENV_NAME (tbown)' >> ~/.bashrc; fi"

echo
echo "Done: $ENV_NAME is in $ROOT on $SERVER, and TB=$ROOT is set in ~/.bashrc there (new shells)."
echo "Next:  ${DEST:+ssh $SERVER   then }follow the guide's server steps (or: cd \$TB && ./deploy-all.sh)."
