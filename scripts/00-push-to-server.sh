#!/usr/bin/env bash
# 00-push-to-server.sh — run on your WORKSTATION, inside your copy of this package.
#
# Copies the stack folders, the scripts and the seed data to the server, into a folder called tbApps
# under the parent folder you choose (where you keep your Docker apps). Safe to run again after you
# update the package: it never overwrites or deletes what belongs to the server (.env / .env.local
# files, runtime-config.json, uploaded files).
#
#   bash scripts/00-push-to-server.sh myserver                  # asks for the parent folder
#   bash scripts/00-push-to-server.sh myserver /docker/compose  # -> /docker/compose/tbApps
#   bash scripts/00-push-to-server.sh local /docker/compose     # this machine itself (no ssh)
#
# The parent folder must be a FULL path, starting with /  - for example /docker/compose, /srv/docker or
# /home/<you>. Your answer is remembered per server for the next run (file .push-targets, not in git).
# It also sets TB=<that folder>/tbApps in the server user's ~/.bashrc, so the guide's commands
# (cd $TB/tbbe && ./deploy.sh) work as written.
set -euo pipefail
SERVER="${1:?usage: bash scripts/00-push-to-server.sh <server> [parent folder]   (<server> = a Host from ~/.ssh/config, or local)}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"
SAVED="$PKG/.push-targets"

if [ "$SERVER" = local ]; then
  run() { bash -c "$1"; }; DEST=""
else
  run() { ssh "$SERVER" "$1"; }; DEST="$SERVER:"
fi

command -v rsync >/dev/null || { echo "rsync is missing on this workstation (sudo apt install rsync)."; exit 1; }
if [ "$SERVER" != local ] && ! ssh -o ConnectTimeout=10 "$SERVER" true; then
  echo "Cannot ssh to $SERVER (see the message above). Check the Host in ~/.ssh/config and that the server runs SSH."
  echo "If $SERVER is this machine itself, use:  bash scripts/00-push-to-server.sh local <parent folder>"
  exit 1
fi
run 'command -v rsync >/dev/null' || { echo "rsync is missing on $SERVER - your server admin installs it (sudo apt install rsync)."; exit 1; }

# --- where on the server ---------------------------------------------------------------------------
PARENT="${2:-}"
if [ -z "$PARENT" ]; then
  last=$(grep -s "^$SERVER=" "$SAVED" | tail -1 | cut -d= -f2-)
  echo "Where do you keep Docker apps on $SERVER? Give the FULL path of that folder, starting with /"
  echo "(for example /docker/compose or /home/<you>). A folder tbApps is created inside it for Timebars."
  read -r -p "Parent folder${last:+ (press Enter for $last)}: " PARENT
  PARENT=${PARENT:-$last}
fi
PARENT=${PARENT%/}
case "$PARENT" in
  /*) ;;
  *) echo "'$PARENT' is not a full path: it must start with /  (e.g. /docker/compose, not docker/compose)."; exit 1 ;;
esac
case "$PARENT" in *[[:space:]]*) echo "The path must not contain spaces."; exit 1 ;; esac
run "[ -d '$PARENT' ]" || { echo "$PARENT does not exist on $SERVER - create it first, or check the spelling."; exit 1; }

# An earlier install that already lives directly in the given folder (e.g. ~/docker) is updated in place.
if [ "${PARENT##*/}" = tbApps ] || run "[ -f '$PARENT/scripts/deploy-common.sh' ]"; then
  ROOT="$PARENT"
else
  ROOT="$PARENT/tbApps"
fi
run "mkdir -p '$ROOT/scripts' '$ROOT/seed' '$ROOT/tbbe/public/uploads'" || {
  echo "Cannot create $ROOT on $SERVER. If $PARENT belongs to root, run there once:"
  echo "  sudo mkdir -p $ROOT && sudo chown \$USER: $ROOT"
  exit 1
}
{ grep -sv "^$SERVER=" "$SAVED" || true; echo "$SERVER=$PARENT"; } > "$SAVED.tmp" && mv "$SAVED.tmp" "$SAVED"

# --- copy ------------------------------------------------------------------------------------------
KEEP=(--exclude '.env' --exclude '.env.local' --exclude 'runtime-config.json' --exclude 'public/uploads/***' --exclude '.gitkeep')
rsync -rlt --itemize-changes "${KEEP[@]}" "$PKG/docker/"  "$DEST$ROOT/"
rsync -rlt --itemize-changes --exclude '00-push-to-server.sh' "$PKG/scripts/" "$DEST$ROOT/scripts/"
rsync -rlt --itemize-changes "$PKG/seed/"    "$DEST$ROOT/seed/"
rsync -rlt --itemize-changes "$PKG/VERSION.md" "$PKG/INSTALLATION_AND_CONFIGURATION_OF_THE_TIMEBARS_SYSTEM_CONTAINER_OPTION.md" "$DEST$ROOT/"
run "chmod 755 '$ROOT'/scripts/*.sh '$ROOT'/*/deploy.sh '$ROOT'/postgres/initdb/*.sh"

# --- TB in the server user's ~/.bashrc --------------------------------------------------------------
run "touch ~/.bashrc; if grep -q '^export TB=' ~/.bashrc; then sed -i 's#^export TB=.*#export TB=$ROOT    \# Timebars apps (tbown)#' ~/.bashrc; else echo 'export TB=$ROOT    # Timebars apps (tbown)' >> ~/.bashrc; fi"

echo
echo "Done: package is in $ROOT on $SERVER ($(git -C "$PKG" describe --tags --always 2>/dev/null || echo 'no git'))."
echo "TB=$ROOT is set in ~/.bashrc on $SERVER (new shells; in an open one run: export TB=$ROOT)."
echo "Next: ${DEST:+ssh $SERVER, and }continue with the installation guide (first install: section 6)."
