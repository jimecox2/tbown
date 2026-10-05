#!/usr/bin/env bash
# 01-setup-host.sh — prepare a fresh Ubuntu LTS server for the Timebars stack.
# Run once, over SSH, as your admin user:   sudo bash scripts/01-setup-host.sh
#
# Does: OS updates, automatic security updates, time zone, a swap file (if none), firewall
# (SSH from your admin network only). Safe to run again.
# Settings (override on the command line, e.g. TZ_NAME=Europe/London sudo -E bash ...):
set -euo pipefail
TZ_NAME="${TZ_NAME:-America/New_York}"
SSH_FROM="${SSH_FROM:-192.168.1.0/24}"     # your admin network (CIDR); SSH is allowed from here only
SWAP_GB="${SWAP_GB:-4}"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

echo "== Server check (minimum: 2 cores, 4 GB RAM, 100 GB disk)"
cores=$(nproc); ram_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
disk_gb=$(df -BG --output=size / | tail -1 | tr -dc 0-9)
echo "   cores=$cores  ram=${ram_gb}GB  disk=${disk_gb}GB  os=$(. /etc/os-release; echo "$PRETTY_NAME")"
[ "$cores" -ge 2 ] && [ "$ram_gb" -ge 3 ] && [ "$disk_gb" -ge 90 ] || echo "   WARNING: below the minimum size."

echo "== Updates and automatic security updates"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install unattended-upgrades ca-certificates curl unzip ufw
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== Time zone: $TZ_NAME"
timedatectl set-timezone "$TZ_NAME"

echo "== Swap"
if swapon --show --noheadings | grep -q .; then
  echo "   swap already present:"; swapon --show
else
  fallocate -l "${SWAP_GB}G" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "   created ${SWAP_GB} GB /swapfile"
fi

echo "== Firewall: SSH from $SSH_FROM only (app ports stay on 127.0.0.1)"
ufw allow from "$SSH_FROM" to any port 22 proto tcp
ufw --force enable
ufw status verbose

echo "Done. Reboot if a new kernel was installed: [ -f /var/run/reboot-required ] && sudo reboot"
