#!/bin/bash
# Pulls jimecox807/tbhelpapp:<tag>, writes it to .env (HELPAPP_TAG, no secrets) and (re)starts it.
# Run from this folder: ./deploy.sh   The key and other secrets live in .env.local (chmod 600), not here.
# Uses the Docker Hub login saved on this server (docker login, once). Never put a token in this file.
cd "$(dirname "$0")" || exit 1

if [ ! -f .env.local ]; then
  echo "Missing .env.local: cp .env.example .env.local, set GEMINI_API_KEY, chmod 600 .env.local"
  exit 1
fi
if ! grep -q '^GEMINI_API_KEY=.' .env.local; then
  echo "GEMINI_API_KEY is not set in .env.local."
  exit 1
fi

current=$(grep -s '^HELPAPP_TAG=' .env | cut -d= -f2)
[ -n "$current" ] && echo "Currently deployed: $current"
read -r -p "Tag to deploy (from VERSION.md): " tag
if [ -z "$tag" ] || [ "$tag" = "latest" ]; then echo "Refusing: give the release tag from VERSION.md (never latest)."; exit 1; fi
image="jimecox807/tbhelpapp:$tag"

if ! docker pull "$image"; then
  echo "Pull failed. Check the tag exists on Docker Hub, or log in: docker login -u jimecox807"
  exit 1
fi

# shared network with the app containers (their nginx proxies /ai/ to this container)
docker network inspect tbhelp >/dev/null 2>&1 || docker network create tbhelp || exit 1

echo "HELPAPP_TAG=$tag" > .env
docker compose up -d || exit 1
docker compose ps

sleep 5
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:3010/api/ai/help)
case "$code" in
  401|400) echo "OK: $image is serving /api/ai/* on port 3010 (answered $code to an empty request, as expected)." ;;
  *)       echo "WARNING: /api/ai/help answered $code - check: docker logs tbhelpapp" ;;
esac
