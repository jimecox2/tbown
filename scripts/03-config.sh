#!/usr/bin/env bash
# 03-config.sh — every setting of this Timebars install lives in ONE file, tbapps.conf.
#
#   bash scripts/03-config.sh new        ask your domain and names, write tbapps.conf (workstation or server)
#   bash $TB/scripts/03-config.sh apply  on the server: generate passwords (first time), write every
#                                        .env.local and runtime-config.json, recreate what changed
#   bash $TB/scripts/03-config.sh check  show what apply would change; writes nothing
#   bash $TB/scripts/03-config.sh import on a server set up before tbapps.conf: make it from the current files
#
# Edit tbapps.conf (nano $TB/tbapps.conf), never the .env.local files: apply rewrites them.
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing (sudo apt install python3)."; exit 1; }
exec python3 "$(dirname "$0")/tbconfig.py" "$@"
