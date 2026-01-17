#!/bin/bash
set -euo pipefail

PORT=22
USERNAME="smoking_gun"
PASSWORD="CCDC-P@ssw0rd"
NEW_PASSWORD="UAUKNOW123#"
IGNORE_USER="blackteam"

# Leave empty to run locally
# OR include 0.0.0.0 to force local execution
HOSTS=(
  0.0.0.0
)

# Main hardening function
harden_system() {
set -euo pipefail

NEW_PASSWORD="UAUKNOW123#"
IGNORE_USER="default"

echo "Updating system..."
apt update -y >/dev/null

echo "Removing services..."
apt remove -y telnet telnetd netcat nc >/dev/null 2>&1 || true

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

# Configuring AppArmor
echo "Enforcing AppArmor..."
systemctl enable --now apparmor
aa-enforce /etc/apparmor.d/* >/dev/null 2>&1 || true

# Hardening SSH and reconfiguring PAM
echo "Hardening SSH..."
SSHD=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSHD
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication no/' $SSHD
sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile none/' $SSHD
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' $SSHD
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' $SSHD

systemctl restart ssh

# Rotate all passwords, allows ignoring users like blackteam
echo "Rotating passwords..."
CURRENT_USER=$(logname 2>/dev/null || whoami)

awk -F: '$3 >= 1000 {print $1}' /etc/passwd | while read -r user; do
  if [[ "$user" == "root" ]] || \
     [[ "$user" == "$CURRENT_USER" ]] || \
     [[ "$user" == "$IGNORE_USER" ]]; then
    echo "  - Skipping $user"
    continue
  fi

  echo "$user:$NEW_PASSWORD" | chpasswd
  echo "  - Rotated password for $user"
done

# Quickly check the crontabs, can mark it down for later
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
}

# Execution logic
run_local=false

[ "${#HOSTS[@]}" -eq 0 ] && run_local=true
for h in "${HOSTS[@]}"; do
  [ "$h" == "0.0.0.0" ] && run_local=true
done

if $run_local; then
  echo "Running locally..."
  [ "$(id -u)" -ne 0 ] && echo "Must be run as root locally!" && exit 1
  harden_system
  exit 0
fi

# Execute script on a remote host
for HOST in "${HOSTS[@]}"; do
  echo "Connecting to $HOST..."
  sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$HOST" <<EOF
echo "$PASSWORD" | sudo -S bash <<'ROOT_EOF'
$(declare -f harden_system)
harden_system
ROOT_EOF
EOF
  echo "Finished $HOST"
done
