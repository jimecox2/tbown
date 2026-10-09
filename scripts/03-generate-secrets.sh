#!/usr/bin/env bash
# 03-generate-secrets.sh — create each stack's .env.local from its .env.example and generate every
# password and key that is made on this server. Never overwrites an existing .env.local.
# Values that are yours (addresses, Gemini key, tunnel token, Stripe ...) keep CHANGE_ME or the example
# value: edit them, and deploy.sh refuses to start a stack while a required one is still CHANGE_ME.
# The Strapi database password is the same in postgres/.env.local and tbbe/.env.local (generated once).
# Run on the server:   bash ~/docker/scripts/03-generate-secrets.sh
set -euo pipefail
ROOT="${1:-$HOME/docker}"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
[ -f "$ROOT/postgres/.env.example" ] || { echo "No stacks in $ROOT - run 00-push-to-server.sh from your workstation first."; exit 1; }
rnd() { openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-40; }
DB_PW=$(rnd)
GENERATED="POSTGRES_PASSWORD PGADMIN_DEFAULT_PASSWORD API_TOKEN_SALT ADMIN_JWT_SECRET TRANSFER_TOKEN_SALT JWT_SECRET NEXTAUTH_SECRET"

for s in postgres tbbe tbwww tbhelp cloudflared; do
  d="$ROOT/$s"
  [ -f "$d/.env.example" ] || continue
  if [ -f "$d/.env.local" ]; then echo "kept:    $d/.env.local (already exists)"; continue; fi
  cp "$d/.env.example" "$d/.env.local"; chmod 600 "$d/.env.local"
  sed -i "s|^STRAPI_DB_PASSWORD=CHANGE_ME|STRAPI_DB_PASSWORD=$DB_PW|; s|^DATABASE_PASSWORD=CHANGE_ME|DATABASE_PASSWORD=$DB_PW|" "$d/.env.local"
  sed -i "s|^APP_KEYS=CHANGE_ME|APP_KEYS=$(rnd),$(rnd),$(rnd),$(rnd)|" "$d/.env.local"
  for v in $GENERATED; do sed -i "s|^$v=CHANGE_ME\$|$v=$(rnd)|" "$d/.env.local"; done
  echo "created: $d/.env.local"
done
[ -f "$ROOT/tbrun/runtime-config.json" ] || { cp "$ROOT/tbrun/runtime-config.example.json" "$ROOT/tbrun/runtime-config.json"; echo "created: $ROOT/tbrun/runtime-config.json"; }

echo
echo "Now edit the values that are yours (each file's comments say what goes where):"
echo "  $ROOT/tbbe/.env.local         PUBLIC_URL, CORS_ORIGINS, SENDGRID_API_KEY, EMAIL_FROM"
echo "  $ROOT/tbwww/.env.local        NEXTAUTH_URL, CLOUD_API_URL, CLOUD_URL, RUN_URL_*, Stripe and Strapi token"
echo "  $ROOT/tbhelp/.env.local       GEMINI_API_KEY, NEXTAUTH_URL, CLOUD_API_URL, CLOUD_WWW_URL, STRAPI_ADMIN_TOKEN"
echo "  $ROOT/tbrun/runtime-config.json  your app hostnames and addresses"
echo "  $ROOT/cloudflared/.env.local  TUNNEL_TOKEN (paste it)"
echo "Still CHANGE_ME:"
grep -l '=CHANGE_ME' "$ROOT"/*/.env.local 2>/dev/null | while read -r f; do echo "  $f: $(grep -o '^[A-Z_]*=CHANGE_ME' "$f" | cut -d= -f1 | tr '\n' ' ')"; done
