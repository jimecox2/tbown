#!/usr/bin/env bash
# deploy.sh — cloudflared stack (container cloudflared). Same steps as every stack: ../scripts/deploy-common.sh
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=cloudflare/cloudflared
STACK_TAG_VAR=CLOUDFLARED_TAG
STACK_CONTAINER=cloudflared
STACK_REQUIRED="TUNNEL_TOKEN"

stack_after() { docker logs --tail 40 cloudflared 2>&1 | grep -m2 'Registered tunnel connection' | sed 's/^/  /'; }

. ../scripts/deploy-common.sh
