#!/usr/bin/env bash
# apply.sh — on the dev box, in your clone of tbown: make one folder per environment from tbapps.conf.
#   bash scripts/apply.sh                 the environments that have no folder in envs/ yet
#   bash scripts/apply.sh --check         check tbapps.conf, show what would be made; writes nothing
#   bash scripts/apply.sh --force PROD    make envs/PROD again (keeps its secrets.env and running state)
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as yourself."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing (sudo apt install python3)."; exit 1; }
exec python3 "$(dirname "$0")/tbenv.py" "$@"
