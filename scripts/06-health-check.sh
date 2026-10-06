#!/usr/bin/env bash
# 06-health-check.sh — is everything up? Read-only. On the server, any time: bash ~/docker/scripts/06-health-check.sh
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }
FAIL=0
docker info >/dev/null 2>&1 || { echo "Cannot use Docker as $USER. Log out and back in after 01-install-docker.sh (id -nG must list docker)."; exit 1; }
echo "Containers:"
for c in tbpgdb tbbe tbwwwp tbhelpapp tbrun-offline cloudflared; do
  s=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
  if [ "$c" = cloudflared ] && [ "$s" = missing ]; then echo "  --    cloudflared not used (own proxy)"; continue; fi
  [ "$s" = running ] && ok "$c running" || bad "$c $s"
done
echo "Services (this server):"
docker exec tbpgdb pg_isready -q 2>/dev/null && ok "PostgreSQL accepting connections" || bad "PostgreSQL"
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:1337/_health); [ "$code" = 204 ] && ok "Strapi /_health" || bad "Strapi /_health ($code)"
code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3001/);        [ "$code" = 200 ] && ok "Website" || bad "Website ($code)"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:3010/api/ai/help)
case "$code" in 401|400) ok "AI service /api/ai/help (answered $code, as expected without a login)";; *) bad "AI service ($code)";; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:8687/ai/help)
case "$code" in 401|400) ok "App proxy /ai/ reaches the AI service ($code)";; *) bad "App proxy /ai/ ($code) - is tbrun-offline on network tbhelp?";; esac
curl -fsS http://127.0.0.1:8687/sw.js 2>/dev/null | head -1 | grep -q TB-OFFLINE-SW && ok "App + offline worker" || bad "App sw.js"
curl -fsS http://127.0.0.1:8687/runtime-config.json >/dev/null 2>&1 && ok "runtime-config.json served" || bad "runtime-config.json"
echo "Server:"
df -h / | awk 'NR==2 {print "  disk used " $5 " of " $2}'
free -h | awk '/Mem:/ {print "  memory used " $3 " of " $2}'
exit $FAIL
