#!/usr/bin/env bash
# 07-check-urls.sh — check every public address from the outside, through the tunnel or your proxy.
# Read-only. The addresses come from this server's settings, so there is nothing to type:
#   app hosts      $TB/tbrun/runtime-config.json  (sites rows; add more as arguments)
#   Strapi         PUBLIC_URL     in $TB/tbbe/.env.local
#   website        NEXTAUTH_URL   in $TB/tbwww/.env.local
#   Timebars Cloud NEXTAUTH_URL   in $TB/tbhelp/.env.local
#
#   bash $TB/scripts/07-check-urls.sh                     # on the server
#   bash $TB/scripts/07-check-urls.sh ab.rlan.ca tb.rlan.ca   # plus app hosts not in runtime-config.json
#
# Cloudflare answers 530 / 1033 when a hostname has no published application on a running tunnel,
# and 502 when the route exists but the container name or port is wrong (or the container is down).
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"   # the tbApps folder this script lives in
FAIL=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }
note() { printf '  \033[33m--\033[0m    %s\n' "$1"; }
val()  { grep -s "^$1=" "$2" | tail -1 | cut -d= -f2- | sed 's#/*$##'; }
code() { curl -s -o /dev/null -m 20 -w '%{http_code}' "$@"; }
hint() {
  case "$1" in
    000) echo "no answer - DNS name missing, or the tunnel/proxy is down" ;;
    530|1033) echo "Cloudflare has no route for this hostname - add the published application" ;;
    502|503|504) echo "route exists but the container does not answer - check the service name and port, and docker ps" ;;
    *) echo "unexpected answer" ;;
  esac
}

BE=$(val PUBLIC_URL "$ROOT/tbbe/.env.local")
WWW=$(val NEXTAUTH_URL "$ROOT/tbwww/.env.local")
CLOUD=$(val NEXTAUTH_URL "$ROOT/tbhelp/.env.local")
APPS=$(python3 -c 'import json,sys; [print(r["host"]) for r in json.load(open(sys.argv[1])).get("sites",[]) if r.get("host")]' "$ROOT/tbrun/runtime-config.json" 2>/dev/null)
APPS="$APPS $*"
OFFLINE=$(python3 -c 'import json,sys; [print(r["host"]) for r in json.load(open(sys.argv[1])).get("sites",[]) if r.get("offline")]' "$ROOT/tbrun/runtime-config.json" 2>/dev/null)

echo "Strapi ($BE):"
if [ -z "$BE" ] || [ "$BE" = CHANGE_ME ]; then bad "PUBLIC_URL not set in tbbe/.env.local"; else
  c=$(code "$BE/_health"); [ "$c" = 204 ] && ok "/_health 204" || bad "/_health $c - $(hint "$c")"
  c=$(code "$BE/admin"); [ "$c" = 200 ] && ok "/admin 200" || bad "/admin $c - $(hint "$c")"
  c=$(code "$BE/api/products"); case "$c" in 200) ok "/api/products 200";; 403) note "/api/products 403 (not public on this database - fine if the site uses its token)";; *) bad "/api/products $c - $(hint "$c")";; esac
fi

echo "Website ($WWW):"
if [ -z "$WWW" ] || [ "$WWW" = CHANGE_ME ]; then bad "NEXTAUTH_URL not set in tbwww/.env.local"; else
  c=$(code "$WWW/"); [ "$c" = 200 ] && ok "home page 200" || bad "home page $c - $(hint "$c")"
  c=$(code "$WWW/sales/pricing"); [ "$c" = 200 ] && ok "/sales/pricing 200" || bad "/sales/pricing $c - $(hint "$c")"
  curl -s -m 20 "$WWW/robots.txt" | grep -q "Sitemap: $WWW/sitemap.xml" && ok "robots.txt names this site ($WWW)" || bad "robots.txt does not name $WWW - check NEXTAUTH_URL"
  loc=$(curl -s -o /dev/null -m 20 -w '%{redirect_url}' "$WWW/dashboard")
  [ "$loc" = "$CLOUD/dashboard" ] && ok "/dashboard -> $loc" || bad "/dashboard -> '${loc}' (expected $CLOUD/dashboard - check CLOUD_URL in tbwww/.env.local)"
fi

echo "Timebars Cloud ($CLOUD):"
if [ -z "$CLOUD" ] || [ "$CLOUD" = CHANGE_ME ]; then bad "NEXTAUTH_URL not set in tbhelp/.env.local"; else
  c=$(code "$CLOUD/"); [ "$c" = 200 ] && ok "home page 200" || bad "home page $c - $(hint "$c")"
  c=$(code -X POST -H 'Content-Type: application/json' -d '{}' "$CLOUD/api/ai/help")
  case "$c" in 401|400) ok "/api/ai/help $c (needs a login, as expected)";; *) bad "/api/ai/help $c - $(hint "$c")";; esac
fi

echo "Apps:"
[ -n "${APPS// /}" ] || bad "no app hosts: add sites rows to tbrun/runtime-config.json"
for h in $APPS; do
  u="https://$h"
  c=$(code "$u/"); [ "$c" = 200 ] || { bad "$h $c - $(hint "$c")"; continue; }
  curl -s -m 20 "$u/runtime-config.json" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null && rc=yes || rc=no
  sw=$(curl -s -m 20 "$u/sw.js" | head -1 | grep -c TB-OFFLINE-SW)
  ai=$(code -X POST -H 'Content-Type: application/json' -d '{}' "$u/ai/help")
  cors=$(curl -s -o /dev/null -D - -m 20 -X OPTIONS -H "Origin: $u" -H 'Access-Control-Request-Method: POST' "$BE/api/auth/local" | tr -d '\r' | grep -i '^access-control-allow-origin:' | awk '{print $2}')
  msg="$h 200, runtime-config $rc, AI $ai, Strapi CORS ${cors:-none}"
  problems=""
  [ "$rc" = yes ] || problems="$problems runtime-config.json not served;"
  case "$ai" in 401|400) ;; *) problems="$problems /ai/ answered $ai;";; esac
  [ "$cors" = "$u" ] || problems="$problems add $u to CORS_ORIGINS in tbbe/.env.local;"
  if echo "$OFFLINE" | grep -qx "$h" && [ "$sw" != 1 ]; then problems="$problems offline host but sw.js is not the worker;"; fi
  [ -z "$problems" ] && ok "$msg" || bad "$msg -${problems}"
done

echo
[ "$FAIL" = 0 ] && echo "All addresses answer. Next: sign in and test in a browser (installation guide, section 15)." || echo "Fix the FAIL lines above, then run this again."
exit $FAIL
