#!/usr/bin/env bash
# deploy.sh — proxy stack (container tbproxy, Caddy). Same steps as every stack: ../scripts/deploy-common.sh
# Its settings file is the Caddyfile that scripts/apply.sh wrote on the dev box.
cd "$(dirname "$0")" || exit 1
STACK_IMAGE=caddy
STACK_TAG_VAR=CADDY_TAG
STACK_CONTAINER=tbproxy
STACK_REQUIRED=""
STACK_NO_ENV_LOCAL=1

stack_check() {
  [ -f Caddyfile ] || { echo "No Caddyfile - run scripts/apply.sh on the dev box and copy this environment again."; return 1; }
  if [ -z "$(docker ps -q -f name='^tbproxy$')" ]; then
    local busy
    busy=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E '[:.](80|443)$' | sort -u | tr '\n' ' ')
    [ -z "$busy" ] || { echo "Ports 80/443 are already in use on this machine ($busy) - stop that web server first (sudo ss -ltnp shows which), or set PROXY=own for this environment."; return 1; }
  fi
}
stack_check_tag() {
  docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" "caddy:$1" \
    caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>caddy-validate.log \
    || { echo "The Caddyfile is not valid - see $PWD/caddy-validate.log"; return 1; }
  rm -f caddy-validate.log
}
stack_after() {
  if grep -q '^[[:space:]]*local_certs' Caddyfile; then
    echo "  TLS=internal: Caddy signs the certificates itself. Trust its root certificate on each browser machine:"
    echo "    docker cp tbproxy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt"
  else
    echo "  Caddy now asks Let's Encrypt for a certificate per name (the DNS names must point here, ports 80/443 open)."
    sleep 20
    docker logs tbproxy 2>&1 | grep -E 'certificate obtained successfully|could not get certificate' \
      | sed -E 's/.*"identifier":"([^"]+)".*"msg":"([^"]+)".*/  \1: \2/; s/.*"msg":"([^"]+)".*"identifier":"([^"]+)".*/  \2: \1/' | tail -12
  fi
  echo "  Follow it: docker logs -f tbproxy"
}

. ../scripts/deploy-common.sh
