#!/usr/bin/env bash
# 03-generate-secrets.sh — create each stack's .env from its .env.example and fill every
# CHANGE_ME with a new random value. Never overwrites an existing .env.
# The Strapi database password is the same in postgres/.env and tbbe/.env (generated once).
# Run on the server:   bash ~/docker/scripts/03-generate-secrets.sh
set -euo pipefail
ROOT="${1:-$HOME/docker}"
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
[ -f "$ROOT/postgres/.env.example" ] || { echo "No stacks in $ROOT - run 00-push-to-server.sh from your workstation first."; exit 1; }
rnd() { openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-40; }
DB_PW=$(rnd)

fill() {   # $1 = stack folder
  local d="$ROOT/$1"
  [ -f "$d/.env.example" ] || return 0
  if [ -f "$d/.env" ]; then echo "kept:    $d/.env (already exists)"; return 0; fi
  cp "$d/.env.example" "$d/.env"; chmod 600 "$d/.env"
  sed -i "s|^STRAPI_DB_PASSWORD=CHANGE_ME|STRAPI_DB_PASSWORD=$DB_PW|; s|^DATABASE_PASSWORD=CHANGE_ME|DATABASE_PASSWORD=$DB_PW|" "$d/.env"
  sed -i "s|^APP_KEYS=CHANGE_ME|APP_KEYS=$(rnd),$(rnd),$(rnd),$(rnd)|" "$d/.env"
  while grep -q '=CHANGE_ME$' "$d/.env"; do
    sed -i "0,/=CHANGE_ME\$/s|=CHANGE_ME\$|=$(rnd)|" "$d/.env"
  done
  echo "created: $d/.env"
}
for s in postgres tbbe tbwwwp cloudflared; do fill "$s"; done
# AI service: its secrets file is .env.local; the Gemini key is yours, so nothing is generated for it
H="$ROOT/tbhelpapp"
if [ -f "$H/.env.example" ]; then
  if [ -f "$H/.env.local" ]; then echo "kept:    $H/.env.local (already exists)"
  else cp "$H/.env.example" "$H/.env.local"; chmod 600 "$H/.env.local"; echo "created: $H/.env.local"; fi
fi
echo
echo "Now edit the values that are yours (addresses, email key, tunnel token):"
echo "  $ROOT/tbbe/.env          BE_URL, FE_URL, SENDGRID_API_KEY"
echo "  $ROOT/tbwwwp/.env        your addresses"
echo "  $ROOT/tbhelpapp/.env.local   GEMINI_API_KEY (your own Google Gemini key; AI needs it)"
echo "  $ROOT/cloudflared/.env   TUNNEL_TOKEN (paste it; cloudflared will not start without it)"
