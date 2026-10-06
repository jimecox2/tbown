#!/bin/bash
# Pulls jimecox807/tbrun:offline-<tag> and (re)starts the app. Run from this folder: ./deploy.sh
# Uses the Docker Hub login saved on this server (docker login, once). Never put a token in this file.
cd "$(dirname "$0")" || exit 1

if [ ! -f runtime-config.json ]; then
  echo "Missing runtime-config.json: cp runtime-config.example.json runtime-config.json and edit your addresses."
  exit 1
fi
python3 -m json.tool runtime-config.json >/dev/null 2>&1 || { echo "runtime-config.json is not valid JSON."; exit 1; }

current=$(grep -s '^OFFLINE_TAG=' .env | cut -d= -f2)
[ -n "$current" ] && echo "Currently deployed: $current"
read -r -p "Offline tag to deploy (e.g. v2 -> offline-v2): " tag
tag=${tag#offline-}
if [ -z "$tag" ] || [ "$tag" = "latest" ]; then
  echo "Refusing: give a release tag such as v2 (never latest). See VERSION.md."
  exit 1
fi
image="jimecox807/tbrun:offline-$tag"

docker pull "$image" || { echo "Pull failed: check the tag (VERSION.md) and your docker login."; exit 1; }
# shared network with the AI service: the app's nginx proxies /ai/ to tbhelpapp
docker network inspect tbhelp >/dev/null 2>&1 || docker network create tbhelp || exit 1

echo "OFFLINE_TAG=offline-$tag" > .env
docker compose up -d || exit 1
docker compose ps

sleep 2
if curl -fsS http://127.0.0.1:8687/sw.js | head -1 | grep -q "TB-OFFLINE-SW" \
   && curl -fsS http://127.0.0.1:8687/runtime-config.json >/dev/null; then
  echo "OK: $image is serving the app, the offline worker and your runtime-config.json on 127.0.0.1:8687."
else
  echo "WARNING: check docker logs tbrun-offline (sw.js or runtime-config.json not served)."
fi
