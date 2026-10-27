#!/usr/bin/env bash
# deploy-common.sh — the steps every stack's deploy.sh runs, so all stacks deploy the same way.
# Not run on its own: each <env folder>/<stack>/deploy.sh sets a few values and sources this file.
#
#   1. refuses sudo, checks Docker access
#   2. checks .env.local (settings, from apply) and .secrets.env (keys and passwords, made by
#      scripts/03-make-passwords.sh where this runs): both exist, chmod 600, required values filled in
#   3. creates the shared network tbnet if it is missing
#   4. the image tag: asks (Enter = the deployed one, or the one in VERSION.md); never "latest".
#      A stack with several images (tbblog) asks once per image, each with its own default.
#      TB_AUTO=1 (deploy-all.sh) offers the newer of the deployed one and VERSION.md; TB_YES=1
#      (deploy-all.sh --yes), or no terminal to ask on, takes that offer without asking.
#   5. pulls the image, writes the tag(s) to .env (nothing else in .env), docker compose up -d
#   6. waits for the container's health check and prints the result
#
# Values set by the stack's deploy.sh before sourcing:
#   STACK_IMAGE      image without tag, e.g. jimecox807/tbwwwp
#   STACK_TAG_VAR    name of the tag variable in .env, e.g. TBWWW_TAG
#   STACK_CONTAINER  container name, e.g. tbwwwp
#   STACK_REQUIRED   settings that must be set in .env.local or .secrets.env (space separated; may be empty)
#   STACK_NO_ENV_LOCAL=1  the stack has neither file (tbrun: runtime-config.json; proxy: Caddyfile)
#   STACK_ENV_DIRS   sub-folders that each hold .env.local and .secrets.env, one per container (tbblog: "strapi web");
#                    unset = the stack folder itself
#   STACK_TAGS       stacks with several images, each with its own tag: "VAR=image VAR=image"
#                    (tbblog: "TBBLOG_STRAPI_TAG=jimecox807/tbblog-strapi TBBLOG_WEB_TAG=jimecox807/tbblog-web");
#                    unset = "$STACK_TAG_VAR=$STACK_IMAGE"
#   STACK_OLD_TAG_VAR  an older tag variable in .env, offered when a STACK_TAGS variable is not there yet
#                    (tbblog: TBBLOG_TAG, the one tag both blog images had before)
# Optional functions:
#   stack_check          extra checks before deploying (return non-zero to stop)
#   stack_check_tag TAG  checks on the chosen tag (return non-zero to stop)
#   stack_after          extra checks after the container is healthy

set -uo pipefail
# where the apps listen: 127.0.0.1, or LISTEN_IP (PROXY=own, proxy on another machine)
LISTEN_IP=$(grep -s '^LISTEN_IP=' ../environment.env | cut -d= -f2-); LISTEN_IP=${LISTEN_IP:-127.0.0.1}
die() { echo "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run ./deploy.sh WITHOUT sudo, as your admin user."
docker info >/dev/null 2>&1 || die "Cannot use Docker as $USER (id -nG must list docker; log out and in after scripts/01-install-docker.sh)."

# --- 2. settings ------------------------------------------------------------------------------
if [ "${STACK_NO_ENV_LOCAL:-}" != 1 ]; then
  files=""
  for d in ${STACK_ENV_DIRS:-.}; do
    [ -f $d/.env.local ] || die "Missing $d/.env.local - this environment folder is incomplete: run scripts/apply.sh on the dev box again (--force)."
    [ -f $d/.secrets.env ] || die "Missing $d/.secrets.env - run ../deploy-all.sh (it makes it from ../secrets.env), or: bash ../scripts/03-make-passwords.sh"
    for f in $d/.env.local $d/.secrets.env; do
      if [ "$(stat -c %a $f)" != 600 ]; then chmod 600 $f && echo "Set $f to chmod 600."; fi
    done
    files="$files $d/.env.local $d/.secrets.env"
  done
  missing=""
  for v in ${STACK_REQUIRED:-}; do      # NAME, or dir/NAME for one container's files
    case "$v" in */*) look="${v%%/*}/.env.local ${v%%/*}/.secrets.env"; v=${v#*/} ;; *) look=$files ;; esac
    val=$(grep -hE "^$v=" $look | tail -1 | cut -d= -f2-)
    [ -z "$val" ] && missing="$missing $v"
  done
  [ -z "$missing" ] || die "Not set:$missing - fill it in ../secrets.env, then run ../deploy-all.sh"
fi
if declare -F stack_check >/dev/null; then stack_check || exit 1; fi

# --- 3. network -------------------------------------------------------------------------------
if ! docker network inspect tbnet >/dev/null 2>&1; then
  docker network create tbnet >/dev/null || die "Could not create the Docker network tbnet."
  echo "Created the shared Docker network tbnet."
fi

# --- 4. tag -----------------------------------------------------------------------------------
pulls=""
old_tag=$( [ -n "${STACK_OLD_TAG_VAR:-}" ] && grep -s "^$STACK_OLD_TAG_VAR=" .env | cut -d= -f2-)
envlines=""; previous=""; deployed=""
for pair in ${STACK_TAGS:-"$STACK_TAG_VAR=$STACK_IMAGE"}; do
  var=${pair%%=*}; img=${pair#*=}
  current=$(grep -s "^$var=" .env | cut -d= -f2-); current=${current:-$old_tag}
  listed=$(awk -F'|' -v img="\`$img\`" '$3 ~ img {gsub(/[ `]/,"",$4); if ($4 ~ /^[0-9A-Za-z][0-9A-Za-z._-]*$/) print $4; exit}' ../VERSION.md 2>/dev/null)
  echo "$img - deployed now: ${current:-nothing}    In VERSION.md: ${listed:-not listed}"
  default=${current:-$listed}
  if [ "${TB_AUTO:-}" = 1 ]; then
    # deploy-all.sh offers the newer of the running tag and VERSION.md (release tags are dates)
    default=$(printf '%s\n' "$current" "$listed" | grep -v '^$' | sort -V | tail -1)
  fi
  what=${PWD##*/}; [ -n "${STACK_TAGS:-}" ] && what="$what (${img##*/})"
  if [ "${TB_YES:-}" = 1 ] || [ ! -t 0 ]; then
    tag=$default
    echo "Tag to deploy for $what: $tag"
  else
    read -r -p "Tag to deploy for $what (press Enter for '${default}'): " tag
    tag=${tag:-$default}
  fi
  [ -n "$tag" ] || die "No tag given for $img. The tags are in ../VERSION.md."
  [ "$tag" != latest ] || die "Refusing 'latest': give a release tag (VERSION.md), so a rollback is just the previous tag."
  if declare -F stack_check_tag >/dev/null; then stack_check_tag "$tag" || exit 1; fi
  envlines="$envlines$var=$tag"$'\n'
  previous="$previous${current:+ $var=$current}"
  deployed="$deployed $img:$tag"
  pulls="$pulls $img:$tag"
done

# --- 5. pull and start ------------------------------------------------------------------------
# Release tags never change, so an image already on this machine is used as is (TB_PULL=1 pulls anyway)
for ref in $pulls; do
  if [ "${TB_PULL:-}" = 1 ] || ! docker image inspect "$ref" >/dev/null 2>&1; then
    docker pull "$ref" || die "Pull failed for $ref: check the tag exists, and your login (docker login)."
  fi
done
printf '%s' "$envlines" > .env
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
    echo "OK: $STACK_CONTAINER is $state;${deployed}" ;;
  *)
    die "WARNING: $STACK_CONTAINER is '${state:-missing}'. Look at: docker logs --tail 50 $STACK_CONTAINER   (roll back: ./deploy.sh and the previous tag${previous:+:$previous})" ;;
esac
