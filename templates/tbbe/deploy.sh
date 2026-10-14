#!/usr/bin/env bash
# deploy.sh — tbbe stack (container tbbe, Strapi). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbbe
STACK_TAG_VAR=TBBE_TAG
STACK_CONTAINER=tbbe
STACK_REQUIRED="DATABASE_PASSWORD APP_KEYS API_TOKEN_SALT ADMIN_JWT_SECRET TRANSFER_TOKEN_SALT JWT_SECRET PUBLIC_URL CORS_ORIGINS"

stack_check() {
  mkdir -p public/uploads
  # Strapi runs as uid 1000 (node) and writes uploaded files here
  if [ "$(stat -c %u public/uploads)" != 1000 ]; then
    echo "Strapi (uid 1000) must own public/uploads:  sudo chown -R 1000:1000 public/uploads"
    sudo chown -R 1000:1000 public/uploads || return 1
  fi
  docker inspect -f '{{.State.Status}}' tbpgdb 2>/dev/null | grep -q running || { echo "Start the database first: cd ../postgres && ./deploy.sh"; return 1; }
}
stack_after() {
  local code; code=$(curl -s -o /dev/null -w '%{http_code}' http://$LISTEN_IP:1337/_health)
  [ "$code" = 204 ] && echo "  Strapi /_health answers 204" || echo "  WARNING: Strapi /_health answered $code"
}

. ../scripts/deploy-common.sh
