#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo permissions!"
  exit 1
fi

read -s -p "Enter your new password: " new_password
echo

echo "Updating system..."
apt update >/dev/null

echo "Removing services..."
apt remove -y telnet telnetd netcat netcat-openbsd netcat-traditional >/dev/null 2>&1 || true

echo "Installing security tools..."
apt install -y \
  rsync \
  git \
  curl \
  fail2ban \
  apparmor \
  apparmor-utils \
  lynis >/dev/null

# Setup linPEAS for use later
echo "Installing linPEAS..."
mkdir -p /opt/linpeas
curl -fsSL https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh \
  -o /opt/linpeas/linpeas.sh
chmod 700 /opt/linpeas/linpeas.sh

# Configure Fail2Ban for the system
echo "Configuring fail2ban..."
cat >/etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
JAIL

systemctl enable --now fail2ban

# Hardening SSH
echo "Hardening SSH..."
SSHD=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD"

sshd -t && systemctl restart ssh

# Rotate all passwords except ignored users
CURRENT_USER=${SUDO_USER:-$(whoami)}

echo "Updating root password..."
echo "root:$new_password" | chpasswd

if [[ "$CURRENT_USER" != "root" ]]; then
  echo "Updating password for $CURRENT_USER..."
  echo "$CURRENT_USER:$new_password" | chpasswd
fi

# Check crontabs
echo "Checking crontabs..."
cut -d: -f1 /etc/passwd | while read -r u; do
  crontab -u "$u" -l >/dev/null 2>&1 && echo "  - Crontab exists for $u"
done

# Determine invoking user's home directory
INVOKING_USER=${SUDO_USER:-root}
INVOKING_HOME=$(eval echo "~$INVOKING_USER")

# Backup important directories
echo "Creating backup directory..."
BACKUP_DIR="$INVOKING_HOME/.mongosux/backups"
mkdir -p "$BACKUP_DIR"

echo "Backing up /etc..."
rsync -a /etc "$BACKUP_DIR/"

echo "Backing up /bin..."
rsync -a /usr/bin "$BACKUP_DIR/"

unset new_password

# Quick check for linux persistence
echo "Listing SUID binaries..."
find / -perm -4000 -type f 2>/dev/null > "$BACKUP_DIR/suid-binaries.txt"

echo "Hardening complete."
