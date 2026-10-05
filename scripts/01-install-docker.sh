#!/usr/bin/env bash
# 01-install-docker.sh — Docker Engine + Compose v2 from Docker's own apt repository
# (falls back to Ubuntu's packages if Docker has no repository for this release yet).
# Also: log rotation for all containers, and your user in the docker group.
# Run once, on the server:   sudo bash ~/docker/scripts/01-install-docker.sh   then log out and in.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }
ADMIN_USER="${SUDO_USER:-$USER}"
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

echo "== Prerequisites (as in Docker's own install steps)"
apt-get update
apt-get -y install ca-certificates curl

# Does Docker publish a repository for this Ubuntu release? 200 = yes, 404 = not yet, else stop.
code=$(curl -s -o /dev/null -w '%{http_code}' "https://download.docker.com/linux/ubuntu/dists/${CODENAME}/Release" || true)
case "$code" in
  200) SOURCE=docker ;;
  404) SOURCE=ubuntu ;;
  *)   echo "Cannot reach download.docker.com (HTTP '$code'). Check the server's internet access / proxy, then run again."; exit 1 ;;
esac

if [ "$SOURCE" = docker ]; then
  # Ubuntu's own Docker packages conflict with Docker's. Replace them only while nothing runs on them.
  if dpkg -s docker.io >/dev/null 2>&1; then
    if [ -n "$(docker ps -aq 2>/dev/null)" ]; then
      echo "Ubuntu's docker.io is installed and has containers - not replacing it. Stop and remove them first, or keep docker.io."
      exit 1
    fi
    echo "== Replacing Ubuntu's docker.io packages (no containers yet) with Docker's"
    apt-get -y remove docker.io docker-compose-v2 docker-buildx containerd runc || true
  fi
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
docker version --format "Docker {{.Server.Version}} (from: $SOURCE packages)"
docker compose version
echo "Done. Log out and back in so '$ADMIN_USER' can run docker without sudo."
