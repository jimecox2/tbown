#!/usr/bin/env bash
# deploy.sh — tbrun stack (container tbrun, the app). Same steps as every stack: ../scripts/deploy-common.sh
# The app has no secrets: its settings file is runtime-config.json (addresses only), not .env.local.
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=jimecox807/tbrun
STACK_TAG_VAR=TBRUN_TAG
STACK_CONTAINER=tbrun
STACK_REQUIRED=""
STACK_NO_ENV_LOCAL=1

stack_check() {
  [ -f runtime-config.json ] || { echo "Missing runtime-config.json: cp runtime-config.example.json runtime-config.json and edit your addresses."; return 1; }
  python3 -m json.tool runtime-config.json >/dev/null 2>&1 || { echo "runtime-config.json is not valid JSON."; return 1; }
}
stack_after() {
  curl -fsS http://127.0.0.1:8687/sw.js | head -1 | grep -q TB-OFFLINE-SW && echo "  app and offline worker served" || echo "  WARNING: sw.js is not the offline worker"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8687/ai/help)
  case "$code" in 401|400) echo "  /ai/ reaches the AI service ($code)" ;; *) echo "  NOTE: /ai/ answered $code - AI needs the tbhelp stack running" ;; esac
}

. ../scripts/deploy-common.sh
