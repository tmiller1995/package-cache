#!/usr/bin/env bash
# One-time setup for a fresh OVHcloud VPS running Ubuntu 24.04.
# Run as the default "ubuntu" user (the one OVH put your SSH key on):
#   curl -fsSL https://raw.githubusercontent.com/tmiller1995/package-cache/main/ovh/bootstrap-vps.sh -o bootstrap-vps.sh
#   sudo bash bootstrap-vps.sh
#
# Installs Docker, locks SSH to keys only, enables the firewall (SSH only),
# turns on unattended security updates, clones this repo to /opt/package-cache
# and installs the nightly Postgres dump.
set -euo pipefail

REPO_URL="https://github.com/tmiller1995/package-cache.git"
APP_DIR="/opt/package-cache"
DATA_DIR="/srv/package-cache-data"
ADMIN_USER="${SUDO_USER:-ubuntu}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo." >&2
  exit 1
fi

# Refuse to disable password logins unless key login already works for the
# admin user, otherwise this script could lock you out.
if [[ ! -s "/home/${ADMIN_USER}/.ssh/authorized_keys" ]]; then
  echo "/home/${ADMIN_USER}/.ssh/authorized_keys is empty; add your SSH key first." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y ca-certificates curl git rsync ufw unattended-upgrades fail2ban

# Docker Engine + Compose plugin from Docker's apt repository.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck source=/dev/null
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "${ADMIN_USER}"

# Keep container logs from filling the disk.
cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "local",
  "log-opts": { "max-size": "20m", "max-file": "5" }
}
JSON
systemctl restart docker

# SSH: keys only, no root login.
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
CONF
systemctl reload ssh

# Firewall: SSH in, everything else denied. No container publishes a host
# port (cloudflared dials out to Cloudflare), so Docker's habit of bypassing
# ufw for published ports does not apply here.
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable

systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades

# App checkout and data directories. Nexus runs as UID 200.
if [[ ! -d "${APP_DIR}/.git" ]]; then
  git clone "${REPO_URL}" "${APP_DIR}"
fi
chown -R "${ADMIN_USER}:${ADMIN_USER}" "${APP_DIR}"
mkdir -p "${DATA_DIR}/nexus-data" "${DATA_DIR}/postgres" "${DATA_DIR}/backups"
chown -R 200:200 "${DATA_DIR}/nexus-data"
chown "${ADMIN_USER}:${ADMIN_USER}" "${DATA_DIR}/backups"

# Nightly logical backup of the Nexus database at 03:17 server time.
cat > /etc/cron.d/package-cache-backup <<CRON
17 3 * * * ${ADMIN_USER} ${APP_DIR}/ovh/backup.sh >> ${DATA_DIR}/backups/backup.log 2>&1
CRON

echo
echo "Done. Log out and back in so the docker group applies, then follow"
echo "${APP_DIR}/ovh/README.md from step 3."
