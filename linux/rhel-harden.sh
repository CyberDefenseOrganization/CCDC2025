#!/bin/bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo permissions!"
  exit 1
fi

read -s -p "Enter your new password: " new_password
echo

IGNORE_USERS=("blackteam" "black_team" "black-team")

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

# Switch from firewalld to iptables
echo "Switching firewall to iptables..."
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

# Set up Fail2Ban on the system
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

# SSH hardening and configurations
echo "Hardening SSH..."
SSHD=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSHD"
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' "$SSHD"

sshd -t && systemctl restart sshd

# Password rotation
echo "Rotating passwords..."
CURRENT_USER=$(logname 2>/dev/null || whoami)

awk -F: '$3 >= 1000 && $7 !~ /(nologin|false)/ {print $1}' /etc/passwd | while read -r user; do

  skip=false
  for ignore in "${IGNORE_USERS[@]}"; do
    if [[ "$user" == "$ignore" ]]; then
      skip=true
      break
    fi
  done

  if [[ "$user" == "root" ]] || [[ "$user" == "$CURRENT_USER" ]] || [[ "$skip" == true ]]; then
    continue
  fi

  echo "$user:$new_password" | chpasswd
done

# Quick inspection of crontabs
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
rsync -a /bin "$BACKUP_DIR/"

echo "Backing up /sbin..."
rsync -a /sbin "$BACKUP_DIR/"

echo "Hardening complete."
sestatus || true
