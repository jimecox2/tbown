#!/usr/bin/env bash
# 03-config-proxy.sh — tbapps.conf for the PROXY method (guide section 8.3), instead of 03-config.sh new.
# Caddy on this server answers every address with free Let's Encrypt certificates; no Cloudflare.
# It asks: the environment (PROD, STAGING, DEV or TRAINING), its domain, process names (agile / pmrm / ppm)
# or initials (ab / tb / cb), and whether to install the offline service worker.
#
#   bash archive/scripts_v1/03-config-proxy.sh          workstation: writes tbapps.conf in the package folder
#   bash $TB/scripts_v1/03-config-proxy.sh      or on the server: writes $TB/tbapps.conf
# Then, as with the tunnel method: paste your keys, 03-config.sh apply - and 03-config.sh dns for the records.
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing (sudo apt install python3)."; exit 1; }
exec python3 "$(dirname "$0")/tbconfig.py" new-proxy "$@"
