#!/usr/bin/env bash
# 06-health-check.sh — is everything up, and on which tags? Read-only. On the server, any time:
#   bash $TB/scripts/06-health-check.sh
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }
FAIL=0
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"   # the tbApps folder this script lives in
echo "Containers (running tag / tag in VERSION.md):"
for pair in postgres:tbpgdb tbbe:tbbe tbwww:tbwwwp tbhelp:tbhelpapp tbrun:tbrun cloudflared:cloudflared; do
  stack=${pair%%:*}; c=${pair#*:}
  s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$c" 2>/dev/null) || s=missing
  if [ "$c" = cloudflared ] && [ "$s" = missing ]; then continue; fi    # checked below with any other tunnel container
  img=$(docker inspect -f '{{.Config.Image}}' "$c" 2>/dev/null); tag=${img##*:}
  listed=$(awk -F'|' -v img="\`${img%:*}\`" '$3 ~ img {gsub(/[ `]/,"",$4); if ($4 ~ /^[0-9A-Za-z][0-9A-Za-z._-]*$/) print $4; exit}' "$ROOT/VERSION.md" 2>/dev/null)
  note=""; [ -n "$listed" ] && [ "$tag" != "$listed" ] && note="  (VERSION.md: $listed)"
  case "$s" in healthy|running) ok "$c $s, ${tag:-?}$note" ;; *) bad "$c $s - cd $ROOT/$stack && ./deploy.sh" ;; esac
done
docker network inspect tbnet >/dev/null 2>&1 && ok "network tbnet" || bad "network tbnet missing - bash $ROOT/scripts/02-create-volumes.sh"
# A Cloudflare tunnel reaches the apps by container name, so it must be on tbnet - also a tunnel container
# that is not ours (another name, started from Portainer or another compose file). When tbnet is removed
# and made again, such a container is NOT put back on it, and a restart does not help: every address
# then answers 502 from outside while everything here looks fine.
tunnels=$(docker ps --format '{{.Names}} {{.Image}}' | awk '$2 ~ /cloudflared/ {print $1}')
[ -n "$tunnels" ] || echo "  --    no Cloudflare tunnel container running (fine with your own proxy, section 8.2)"
for t in $tunnels; do
  if docker inspect -f '{{range $n, $v := .NetworkSettings.Networks}}{{$n}} {{end}}' "$t" | grep -qw tbnet; then
    ok "tunnel container $t is on tbnet"
  else
    bad "tunnel container $t is NOT on tbnet - every public address answers 502. Fix: docker network connect tbnet $t"
  fi
done
[ -f "$ROOT/tbapps.conf" ] || echo -e "  \033[33m--\033[0m    no $ROOT/tbapps.conf - the containers run on, but 03-config.sh apply needs it (renamed? ls $ROOT/tbapps.conf*)"
echo "Services (this server):"
docker exec tbpgdb pg_isready -q 2>/dev/null && ok "PostgreSQL accepting connections" || bad "PostgreSQL"
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:1337/_health); [ "$code" = 204 ] && ok "Strapi /_health" || bad "Strapi /_health ($code)"
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/);        [ "$code" = 200 ] && ok "Website" || bad "Website ($code)"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:3010/api/ai/help)
case "$code" in 401|400) ok "AI service /api/ai/help (answered $code, as expected without a login)";; *) bad "AI service ($code)";; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8687/ai/help)
case "$code" in 401|400) ok "App proxy /ai/ reaches the AI service ($code)";; *) bad "App proxy /ai/ ($code) - are tbrun and tbhelpapp both on network tbnet?";; esac
curl -fsS http://127.0.0.1:8687/sw.js 2>/dev/null | head -1 | grep -q TB-OFFLINE-SW && ok "App + offline worker" || bad "App sw.js"
curl -fsS http://127.0.0.1:8687/runtime-config.json >/dev/null 2>&1 && ok "runtime-config.json served" || bad "runtime-config.json"
echo "Server:"
df -h / | awk 'NR==2 {print "  disk used " $5 " of " $2}'
free -h | awk '/Mem:/ {print "  memory used " $3 " of " $2}'
exit $FAIL
