#!/usr/bin/env bash
# deploy.sh — tbhelp stack (container tbhelpapp). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbhelpapp
STACK_TAG_VAR=HELPAPP_TAG
STACK_CONTAINER=tbhelpapp
STACK_REQUIRED="GEMINI_API_KEY STRAPI_URL NEXTAUTH_SECRET NEXTAUTH_URL"

stack_after() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:3010/api/ai/help)
  case "$code" in
    401|400) echo "  AI routes answer $code to an empty request, as expected" ;;
    *)       echo "  WARNING: /api/ai/help answered $code - docker logs tbhelpapp" ;;
  esac
}

. ../scripts/deploy-common.sh
