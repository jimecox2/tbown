#!/usr/bin/env bash
# 03-make-passwords.sh — make this environment's passwords, here on its server, and hand each stack its own.
#   bash $TB/scripts/03-make-passwords.sh
# The first run fills every empty password in $TB/secrets.env with a strong random value; later runs keep
# them. Paste the keys (Gemini, SendGrid, Stripe, later the Strapi API token) into secrets.env with nano,
# then run this again: it copies them to the stacks. Never change a database password after the first deploy.
set -euo pipefail
[ "$(id -u)" -ne 0 ] || { echo "Run this WITHOUT sudo, as your admin user."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing (sudo apt install python3)."; exit 1; }
exec python3 "$(dirname "$0")/make-secrets.py"
