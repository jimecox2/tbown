#!/usr/bin/env bash
# 02-install-docker.sh — Docker Engine + Compose v2 from Docker's own apt repository
# (falls back to Ubuntu's packages if Docker has no repository for this release yet).
# Also: log rotation for all containers, and your user in the docker group.
# Run once:   sudo bash scripts/02-install-docker.sh      then log out and back in.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
ADMIN_USER="${SUDO_USER:-$USER}"
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

if curl -fsI "https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release" >/dev/null; then
  echo "== Docker's apt repository ($CODENAME)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.sources <<SRC
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
SRC
  apt-get update
  apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  echo "== Docker has no repository for '$CODENAME' yet - using Ubuntu's packages"
  apt-get update
  apt-get -y install docker.io docker-compose-v2 docker-buildx
fi

echo "== Log rotation (10 MB x 3 files per container)"
mkdir -p /etc/docker
if [ -s /etc/docker/daemon.json ]; then
  echo "   /etc/docker/daemon.json exists - not changed:"; cat /etc/docker/daemon.json
else
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
JSON
fi
systemctl enable --now docker
systemctl restart docker

usermod -aG docker "$ADMIN_USER"
docker version --format 'Docker {{.Server.Version}}'
docker compose version
echo "Done. Log out and back in so '$ADMIN_USER' can run docker without sudo."
