#!/usr/bin/env bash
# deploy.sh — tbwww stack (container tbwwwp). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbwwwp
STACK_TAG_VAR=TBWWW_TAG
STACK_CONTAINER=tbwwwp
STACK_REQUIRED="NEXTAUTH_SECRET NEXTAUTH_URL"

stack_after() {
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/)
  [ "$code" = 200 ] && echo "  Website home page answers 200" || echo "  WARNING: website home page answered $code (is Strapi up? docker logs tbwwwp)"
}

. ../scripts/deploy-common.sh
