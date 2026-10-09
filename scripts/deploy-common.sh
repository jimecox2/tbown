#!/usr/bin/env bash
# deploy-common.sh — the steps every stack's deploy.sh runs, so all stacks deploy the same way.
# Not run on its own: each <tbApps>/<stack>/deploy.sh sets a few values and sources this file.
#
#   1. refuses sudo, checks Docker access
#   2. checks .env.local (exists, chmod 600, required values filled in) — secrets and addresses
#   3. creates the shared network tbnet if it is missing
#   4. asks for the image tag (Enter = the deployed one, or the one in VERSION.md); never "latest"
#   5. pulls the image, writes the tag to .env (the only line in .env), docker compose up -d
#   6. waits for the container's health check and prints the result
#
# Values set by the stack's deploy.sh before sourcing:
#   STACK_IMAGE      image without tag, e.g. jimecox807/tbwwwp
#   STACK_TAG_VAR    name of the tag variable in .env, e.g. TBWWW_TAG
#   STACK_CONTAINER  container name, e.g. tbwwwp
#   STACK_REQUIRED   settings that must be set in .env.local (space separated; may be empty)
#   STACK_NO_ENV_LOCAL=1  the stack has no .env.local (tbrun: its settings are runtime-config.json)
# Optional functions:
#   stack_check          extra checks before deploying (return non-zero to stop)
#   stack_check_tag TAG  checks on the chosen tag (return non-zero to stop)
#   stack_after          extra checks after the container is healthy

set -uo pipefail
die() { echo "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run ./deploy.sh WITHOUT sudo, as your admin user."
docker info >/dev/null 2>&1 || die "Cannot use Docker as $USER (id -nG must list docker; log out and in after 01-install-docker.sh)."

# --- 2. settings ------------------------------------------------------------------------------
if [ "${STACK_NO_ENV_LOCAL:-}" != 1 ]; then
  if [ ! -f .env.local ]; then
    die "Missing .env.local: run ../scripts/03-generate-secrets.sh, or cp .env.example .env.local, fill it in and chmod 600 .env.local"
  fi
  if [ "$(stat -c %a .env.local)" != 600 ]; then chmod 600 .env.local && echo "Set .env.local to chmod 600."; fi
  missing=""
  for v in ${STACK_REQUIRED:-}; do
    val=$(grep -E "^$v=" .env.local | tail -1 | cut -d= -f2-)
    { [ -z "$val" ] || [ "$val" = CHANGE_ME ]; } && missing="$missing $v"
  done
  [ -z "$missing" ] || die "Not set in .env.local:$missing  (see the comments in .env.example)"
fi
if declare -F stack_check >/dev/null; then stack_check || exit 1; fi

# --- 3. network -------------------------------------------------------------------------------
if ! docker network inspect tbnet >/dev/null 2>&1; then
  docker network create tbnet >/dev/null || die "Could not create the Docker network tbnet."
  echo "Created the shared Docker network tbnet."
fi

# --- 4. tag -----------------------------------------------------------------------------------
current=$(grep -s "^$STACK_TAG_VAR=" .env | cut -d= -f2-)
listed=$(awk -F'|' -v img="\`$STACK_IMAGE\`" '$3 ~ img {gsub(/[ `]/,"",$4); if ($4 ~ /^[0-9A-Za-z][0-9A-Za-z._-]*$/) print $4; exit}' ../VERSION.md 2>/dev/null)
echo "Deployed now: ${current:-nothing}    In VERSION.md: ${listed:-not listed}"
default=${current:-$listed}
read -r -p "Tag to deploy (press Enter for '${default}'): " tag
tag=${tag:-$default}
[ -n "$tag" ] || die "No tag given. The tags are in ../VERSION.md."
[ "$tag" != latest ] || die "Refusing 'latest': give a release tag (VERSION.md), so a rollback is just the previous tag."
if declare -F stack_check_tag >/dev/null; then stack_check_tag "$tag" || exit 1; fi

# --- 5. pull and start ------------------------------------------------------------------------
docker pull "$STACK_IMAGE:$tag" || die "Pull failed: check the tag exists, and your login (docker login)."
echo "$STACK_TAG_VAR=$tag" > .env
docker compose up -d || die "docker compose up failed - see the message above."

# --- 6. health --------------------------------------------------------------------------------
printf 'Waiting for %s' "$STACK_CONTAINER"
state=""
for _ in $(seq 1 60); do
  state=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$STACK_CONTAINER" 2>/dev/null)
  case "$state" in healthy|running|unhealthy|exited|dead) break ;; esac
  printf '.'; sleep 3
done
echo
docker compose ps
case "$state" in
  healthy|running)
    if declare -F stack_after >/dev/null; then stack_after || exit 1; fi
    echo "OK: $STACK_CONTAINER is $state on $STACK_IMAGE:$tag" ;;
  *)
    die "WARNING: $STACK_CONTAINER is '${state:-missing}'. Look at: docker logs --tail 50 $STACK_CONTAINER   (roll back: ./deploy.sh and the previous tag${current:+, $current})" ;;
esac
