#!/usr/bin/env bash
# deploy.sh — proxy stack (container tbproxy, Caddy). Same steps as every stack: ../scripts_v1/deploy-common.sh
# The proxy method only (guide section 8.3). Its settings file is the Caddyfile that 03-config.sh apply writes.
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=caddy
STACK_TAG_VAR=CADDY_TAG
STACK_CONTAINER=tbproxy
STACK_REQUIRED=""
STACK_NO_ENV_LOCAL=1

stack_check() {
  [ -f Caddyfile ] || { echo "No Caddyfile: set up tbapps.conf with ../scripts_v1/03-config-proxy.sh, then: bash ../scripts_v1/03-config.sh apply"; return 1; }
  if [ -z "$(docker ps -q -f name='^tbproxy$')" ]; then
    local busy
    busy=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E '[:.](80|443)$' | sort -u | tr '\n' ' ')
    [ -z "$busy" ] || { echo "Ports 80/443 are already in use on this server ($busy) - stop that web server first (sudo ss -ltnp shows which)."; return 1; }
  fi
}
stack_check_tag() {
  docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" "caddy:$1" \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>caddy-validate.log \
    || { echo "The Caddyfile is not valid - see $PWD/caddy-validate.log"; return 1; }
  rm -f caddy-validate.log
}
stack_after() {
  echo "  Caddy now asks Let's Encrypt for a certificate per name (the DNS records must point here: 03-config.sh dns)."
  sleep 20
  docker logs tbproxy 2>&1 | grep -E 'certificate obtained successfully|could not get certificate|obtaining certificate' \
    | sed -E 's/.*"identifier":"([^"]+)".*"msg":"([^"]+)".*/  \1: \2/; s/.*"msg":"([^"]+)".*"identifier":"([^"]+)".*/  \2: \1/' | tail -12
  echo "  Follow it: docker logs -f tbproxy    Check from outside: bash ../scripts_v1/07-check-urls.sh"
}

. ../scripts_v1/deploy-common.sh
