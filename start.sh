s#!/usr/bin/env bash
set -e

echo "=== VPS BOOTSTRAP (CADDY + PM2) ==="

# ---------- CONFIG ----------
TIMEZONE="Asia/Jakarta"
SWAP_SIZE="2G"
NODE_LTS=true
DISABLE_SSH_PASSWORD=false
# ----------------------------

echo "[1] Update system"
apt update -y
apt upgrade -y

echo "[2] Install base packages"
apt install -y \
  curl wget git unzip zip \
  htop btop net-tools \
  ca-certificates gnupg \
  lsb-release ufw fail2ban

echo "[3] Set timezone"
timedatectl set-timezone $TIMEZONE

# ---------- FIREWALL ----------
echo "[4] Setup firewall"
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# ---------- SWAP ----------
echo "[5] Setup swap"
if ! swapon --show | grep -q swapfile; then
  fallocate -l $SWAP_SIZE /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------- SYSCTL ----------
echo "[6] Tune sysctl"
cat <<EOF >> /etc/sysctl.conf
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl -p

# ---------- NODE ----------
if [ "$NODE_LTS" = true ]; then
  echo "[7] Install Node LTS"
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt install -y nodejs
fi

echo "[8] Install PM2"
npm install -g pm2
pm2 startup systemd -u $SUDO_USER --hp /home/$SUDO_USER || true

# ---------- CADDY ----------
echo "[9] Install Caddy"

apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | tee /etc/apt/sources.list.d/caddy-stable.list

apt update
apt install -y caddy

systemctl enable caddy
systemctl start caddy

# ---------- FAIL2BAN ----------
echo "[10] Enable fail2ban"
systemctl enable fail2ban
systemctl restart fail2ban

# ---------- SSH HARDEN ----------
if [ "$DISABLE_SSH_PASSWORD" = true ]; then
  echo "[11] Disable SSH password login"
  sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  systemctl restart ssh
fi

# ---------- FOLDERS ----------
echo "[12] Create deploy dirs"
mkdir -p /opt/apps
mkdir -p /opt/data
mkdir -p /opt/logs
chown -R $SUDO_USER:$SUDO_USER /opt

echo "[13] Cleanup"
apt autoremove -y

echo "=== DONE ==="
echo "Logout/login again so pm2 + node env clean"
