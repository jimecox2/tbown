#!/usr/bin/env bash
# deploy.sh — tbbe stack (container tbbe, Strapi). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbbe
STACK_TAG_VAR=TBBE_TAG
STACK_CONTAINER=tbbe
STACK_REQUIRED="DATABASE_PASSWORD APP_KEYS API_TOKEN_SALT ADMIN_JWT_SECRET TRANSFER_TOKEN_SALT JWT_SECRET PUBLIC_URL CORS_ORIGINS"

stack_check() {
  mkdir -p public/uploads
  docker inspect -f '{{.State.Status}}' tbpgdb 2>/dev/null | grep -q running || { echo "Start the database first: cd ../postgres && ./deploy.sh"; return 1; }
}
stack_after() {
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:1337/_health)
  [ "$code" = 204 ] && echo "  Strapi /_health answers 204" || echo "  WARNING: Strapi /_health answered $code"
}

. ../scripts/deploy-common.sh
