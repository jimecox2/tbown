#!/usr/bin/env bash
# 00-prep-new-server.sh — make a NEW cloud server (e.g. a DigitalOcean droplet) ready for the guide.
# Run ONCE, as root, on a fresh Ubuntu 24.04 / 26.04 server that you can reach as root with your SSH key
# (DigitalOcean: add your key when you create the droplet). From your workstation:
#
#   scp scripts/00-prep-new-server.sh root@<IP>:
#   ssh -t root@<IP> bash 00-prep-new-server.sh <admin user> [--ssh-from <your IP or CIDR>] [--key "<public key>"]
#
# What it does (the end state of guide section 4):
#   - patches the server (apt full-upgrade) and turns on automatic security updates
#   - installs curl, ca-certificates, rsync, tar, openssl, python3, ufw
#   - creates <admin user> with sudo; asks you for its password (used for sudo only, never for SSH)
#   - gives it root's SSH keys (the ones DigitalOcean put there) plus --key, if given
#   - SSH: keys only, no root login, no passwords - only after the admin user has a key
#   - firewall (ufw): SSH in (from --ssh-from only, if given), everything else in denied
#   - time sync on; swap file on a server with less than 8 GB RAM and no swap
# It does not install Docker: that is guide section 6 (01-install-docker.sh).
# Your organisation's further hardening (fail2ban, auditd, CIS rules ...) goes on top as usual.
set -euo pipefail
die() { echo "ERROR: $*" >&2; exit 1; }

ADMIN="${1:-}"; shift || true
SSH_FROM=""; EXTRA_KEY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ssh-from) SSH_FROM="${2:?--ssh-from needs an address, e.g. 203.0.113.7 or 203.0.113.0/24}"; shift 2 ;;
    --key)      EXTRA_KEY="${2:?--key needs a public key in quotes}"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done
[ -n "$ADMIN" ] || die "usage: bash 00-prep-new-server.sh <admin user> [--ssh-from <IP/CIDR>] [--key \"<public key>\"]"
[[ "$ADMIN" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || die "'$ADMIN' is not a valid user name (lowercase letters, digits, - and _)"
[ "$ADMIN" != root ] || die "choose a user name other than root"
[ "$(id -u)" -eq 0 ] || die "run as root (DigitalOcean: ssh root@<IP>)"
. /etc/os-release
[ "${ID:-}" = ubuntu ] || die "this script is for Ubuntu; this server runs ${PRETTY_NAME:-unknown}"
[ -t 0 ] || die "run it with ssh -t so it can ask for the admin password"
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo "== 1. Updates (a few minutes on a new server)"
apt-get update
"${APT[@]}" full-upgrade
"${APT[@]}" install curl ca-certificates rsync tar openssl python3 ufw unattended-upgrades
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CFG'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CFG

echo "== 2. Admin user $ADMIN"
if id "$ADMIN" >/dev/null 2>&1; then
  echo "$ADMIN exists - keeping it."
else
  adduser --disabled-password --gecos "" "$ADMIN"
fi
usermod -aG sudo "$ADMIN"
if passwd -S "$ADMIN" | awk '{exit !($2=="P")}'; then
  echo "$ADMIN already has a password (used for sudo)."
else
  echo "Choose a password for $ADMIN. It is used for sudo only - SSH accepts keys only. Keep it in your vault."
  until passwd "$ADMIN"; do echo "Try again."; done
fi

echo "== 3. SSH keys for $ADMIN"
HOME_DIR=$(getent passwd "$ADMIN" | cut -d: -f6)
install -d -m 700 -o "$ADMIN" -g "$ADMIN" "$HOME_DIR/.ssh"
AK="$HOME_DIR/.ssh/authorized_keys"
touch "$AK"
{ cat /root/.ssh/authorized_keys 2>/dev/null || true; echo "$EXTRA_KEY"; } | \
  { grep -E '^(ssh-|ecdsa-|sk-)' || true; } | while read -r key; do grep -qxF "$key" "$AK" || echo "$key" >> "$AK"; done
chown "$ADMIN:$ADMIN" "$AK"; chmod 600 "$AK"
NKEYS=$(grep -cE '^(ssh-|ecdsa-|sk-)' "$AK" || true)
[ "$NKEYS" -gt 0 ] || die "no SSH key for $ADMIN (root has none either). Run again with --key \"\$(cat ~/.ssh/id_ed25519.pub)\" from your workstation. SSH was not changed."
echo "$ADMIN has $NKEYS key(s)."

echo "== 4. SSH: keys only, no root login"
# sshd uses the FIRST value it reads; files in sshd_config.d are read in name order, so 00- wins over
# DigitalOcean's 50-cloud-init.conf (which may allow passwords).
cat > /etc/ssh/sshd_config.d/00-timebars.conf <<CFG
# Written by 00-prep-new-server.sh
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 4
AllowUsers $ADMIN
CFG
sshd -t || { rm -f /etc/ssh/sshd_config.d/00-timebars.conf; die "the SSH settings did not pass sshd -t - removed them, SSH unchanged"; }
systemctl reload ssh 2>/dev/null || systemctl restart ssh

echo "== 5. Firewall"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
if [ -n "$SSH_FROM" ]; then
  ufw allow from "$SSH_FROM" to any port 22 proto tcp comment 'SSH from admin network' >/dev/null
else
  ufw allow OpenSSH >/dev/null
fi
ufw --force enable >/dev/null
ufw status verbose | sed 's/^/  /'

echo "== 6. Time and swap"
timedatectl set-ntp true || true
if [ -z "$(swapon --show --noheadings)" ] && [ "$(awk '/MemTotal/ {print int($2/1048576)}' /proc/meminfo)" -lt 8 ]; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "Added a 2 GB swap file."
fi

# public address: DigitalOcean's metadata service, else the first address of this server
IP=$(curl -s -m 3 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address || true)
[ -n "$IP" ] || IP=$(hostname -I | awk '{print $1}')
echo
echo "Done: $PRETTY_NAME, admin user $ADMIN, SSH keys only, firewall on."
[ -f /var/run/reboot-required ] && echo "A reboot is needed for the updates: run   reboot   (then wait a minute)."
cat <<NEXT

KEEP THIS ROOT SESSION OPEN until the test below works.
On your workstation (guide section 3) add to ~/.ssh/config:

  Host $(hostname)
      HostName $IP
      User $ADMIN
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes

then, in a NEW terminal:   ssh $(hostname) 'hostname; sudo -v && echo sudo ok'
Root and password logins are now refused. Next: guide section 5 (00-push-to-server.sh $(hostname)).
NEXT
