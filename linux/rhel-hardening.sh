#!/bin/bash
set -euo pipefail

PORT=22
USERNAME="smoking_gun"
PASSWORD="CCDC-P@ssw0rd"
NEW_PASSWORD="UAUKNOW123#"
IGNORE_USER="blackteam"

HOSTS=(
  0.0.0.0
)

harden_system() {
set -euo pipefail

echo "Updating system..."
dnf -y update >/dev/null

echo "Installing EPEL..."
dnf -y install epel-release >/dev/null

echo "Removing dangerous services..."
dnf -y remove telnet telnet-server nmap-ncat >/dev/null 2>&1 || true

echo "Installing security tools..."
dnf -y install \
  rsync \
  git \
  curl \
  fail2ban \
  iptables-services \
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
systemctl disable --now firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true
systemctl enable --now iptables
systemctl enable --now ip6tables

# SELinux configuration and hardening
echo "Hardening SELinux..."

# Enforce immediately
setenforce 1 || true

# Persist enforcement
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
sed -i 's/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config

# Restore contexts
restorecon -RFv /etc /usr /bin /sbin /var >/dev/null 2>&1 || true

# Harden common daemon behavior
setsebool -P ssh_sysadm_login off
setsebool -P daemons_enable_cluster_mode off
setsebool -P daemons_dump_core off
setsebool -P domain_kernel_load_modules off
setsebool -P secure_mode_policyload on

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

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSHD
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication no/' $SSHD
sed -i 's|^#*AuthorizedKeysFile.*|AuthorizedKeysFile none|' $SSHD
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' $SSHD
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' $SSHD

systemctl restart sshd

# Password rotation for all users barring the exception
echo "Rotating passwords..."
CURRENT_USER=$(logname 2>/dev/null || whoami)

awk -F: '$3 >= 1000 {print $1}' /etc/passwd | while read -r user; do
  if [[ "$user" == "root" ]] || \
     [[ "$user" == "$CURRENT_USER" ]] || \
     [[ "$user" == "$IGNORE_USER" ]]; then
    continue
  fi
  echo "$user:$NEW_PASSWORD" | chpasswd
done

# Quick inspection of the crontab
echo "Checking crontabs..."
for u in $(cut -d: -f1 /etc/passwd); do
  crontab -u "$u" -l >/dev/null 2>&1 && echo "  - Crontab exists for $u"
done

# Backup important directories locally
echo "Creating backup directory..."
BACKUP_DIR="~/.mongosux/backups"
mkdir -p "$BACKUP_DIR"

echo "Backing up /etc..."
rsync -avz /etc "$BACKUP_DIR/"

echo "Backing up /bin..."
rsync -avz /bin "$BACKUP_DIR/"

echo "Backing up /sbin..."
rsync -avz /sbin "$BACKUP_DIR/"

echo "Hardening complete."
sestatus || true
}

# Main script logic
run_local=false

[ "${#HOSTS[@]}" -eq 0 ] && run_local=true
for h in "${HOSTS[@]}"; do
  [ "$h" == "0.0.0.0" ] && run_local=true
done

if $run_local; then
  [ "$(id -u)" -ne 0 ] && echo "Must be root" && exit 1
  harden_system
  exit 0
fi

for HOST in "${HOSTS[@]}"; do
  sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$HOST" <<EOF
echo "$PASSWORD" | sudo -S bash <<'ROOT_EOF'
$(declare -f harden_system)
harden_system
ROOT_EOF
EOF
done
