#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo permissions!"
  exit 1
fi

read -s -p "Enter your new password: " new_password
echo

read -p "Enter subnet to whitelist (format X.X.X.X/X) or press Enter to skip: " whitelist_subnet

WHITELIST_IPS="127.0.0.1/8 ::1"

if [[ $whitelist_subnet =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
  WHITELIST_IPS="$WHITELIST_IPS $whitelist_subnet"
else
  echo "Invalid or empty subnet. Only localhost will be whitelisted."
fi

echo "Updating system..."
dnf -y update --security || true

echo "Installing EPEL..."
dnf -y install epel-release >/dev/null || true

echo "Removing dangerous services..."
dnf -y remove telnet telnet-server nmap-ncat >/dev/null 2>&1 || true

echo "Installing security tools..."
dnf -y install \
  rsync \
  git \
  curl \
  fail2ban \
  lynis \
  policycoreutils-python-utils >/dev/null

# Configure linPEAS for the system
echo "Installing linPEAS..."
mkdir -p /opt/linpeas
curl -fsSL https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh \
  -o /opt/linpeas/linpeas.sh
chmod 700 /opt/linpeas/linpeas.sh

# Firewall configuration
echo "Configuring firewall..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh >/dev/null
firewall-cmd --reload >/dev/null

# SELinux configuration and hardening
echo "Hardening SELinux..."

setenforce 1 || true

sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config

restorecon -Rv /etc/ssh /etc/passwd /etc/shadow /usr/bin /bin /sbin >/dev/null 2>&1 || true

setsebool -P ssh_sysadm_login off || true
setsebool -P daemons_enable_cluster_mode off || true
setsebool -P daemons_dump_core off || true
setsebool -P domain_kernel_load_modules off || true
setsebool -P secure_mode_policyload on || true

# Set up Fail2Ban
echo "Configuring fail2ban..."

mkdir -p /etc/fail2ban/jail.d

cat >/etc/fail2ban/jail.local <<'JAIL'
[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h
JAIL

cat >/etc/fail2ban/jail.d/whitelist.conf <<WHITELIST
[DEFAULT]

ignoreip = $WHITELIST_IPS
WHITELIST

systemctl enable --now fail2ban

# SSH hardening
echo "Hardening SSH..."
SSHD=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD"

sshd -t && systemctl restart sshd

# Password rotation
CURRENT_USER=${SUDO_USER:-$(whoami)}

echo "Updating root password..."
echo "root:$new_password" | chpasswd

if [[ "$CURRENT_USER" != "root" ]]; then
  echo "Updating password for $CURRENT_USER..."
  echo "$CURRENT_USER:$new_password" | chpasswd
fi

# Quick inspection of crontabs
echo "Checking crontabs..."
cut -d: -f1 /etc/passwd | while read -r u; do
  crontab -u "$u" -l >/dev/null 2>&1 && echo "  - Crontab exists for $u"
done

# Backup important directories
echo "Creating backup directory..."
BACKUP_DIR="/opt/.mongosux/backups"
mkdir -p "$BACKUP_DIR"

echo "Backing up /etc..."
rsync -a /etc "$BACKUP_DIR/"

echo "Backing up /usr/bin..."
rsync -a /usr/bin "$BACKUP_DIR/"

unset new_password

# Quick check for linux persistence
echo "Listing SUID binaries..."
find / -perm -4000 -type f 2>/dev/null > "$BACKUP_DIR/suid-binaries.txt"

echo "Hardening complete."
sestatus || true
