#!/bin/bash
set -euo pipefail

PORT=22
USERNAME="lockpick"
PASSWORD="CCDC-Default-P@ssword"
NEW_PASSWORD="UAUKNOW123#"
IGNORE_USER="default"

# Leave empty to run locally
# OR include 0.0.0.0 to force local execution
HOSTS=(
  0.0.0.0
)

# =============================
# HARDENING FUNCTION (ROOT)
# =============================
harden_system() {
set -euo pipefail

NEW_PASSWORD="UAUKNOW123#"
IGNORE_USER="default"

echo "[*] Updating system..."
apt update -y >/dev/null

echo "[*] Removing dangerous services..."
apt remove -y telnet telnetd netcat nc >/dev/null 2>&1 || true

echo "[*] Installing security tools..."
apt install -y \
  rsync \
  git \
  curl \
  fail2ban \
  apparmor \
  apparmor-utils \
  lynis >/dev/null

# -----------------------------
# linPEAS
# -----------------------------
echo "[*] Installing linPEAS..."
mkdir -p /opt/linpeas
curl -fsSL https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh \
  -o /opt/linpeas/linpeas.sh
chmod 700 /opt/linpeas/linpeas.sh

# -----------------------------
# Fail2Ban
# -----------------------------
echo "[*] Configuring fail2ban..."
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

# -----------------------------
# AppArmor
# -----------------------------
echo "[*] Enforcing AppArmor..."
systemctl enable --now apparmor
aa-enforce /etc/apparmor.d/* >/dev/null 2>&1 || true

# -----------------------------
# SSH Hardening (PASSWORD ONLY)
# -----------------------------
echo "[*] Hardening SSH (disabling public keys)..."
SSHD=/etc/ssh/sshd_config

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSHD
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSHD
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication no/' $SSHD
sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile none/' $SSHD
sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' $SSHD
sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' $SSHD

systemctl restart ssh

# -----------------------------
# Password Rotation (WITH IGNORE)
# -----------------------------
echo "[*] Rotating passwords..."
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

# -----------------------------
# Cron Inspection
# -----------------------------
echo "[*] Checking crontabs..."
for u in $(cut -d: -f1 /etc/passwd); do
  crontab -u "$u" -l >/dev/null 2>&1 && echo "  - Crontab exists for $u"
done

# -----------------------------
# Backup /etc only
# -----------------------------
echo "[*] Backing up /etc..."
mkdir -p /root/backups
rsync -a /etc /root/backups/etc-$(date +%F)

# -----------------------------
# Binary reconfiguration (final)
# -----------------------------

if [ -x /usr/bin/sudo ]; then
  install -o root -g root -m 4755 /usr/bin/sudo /usr/bin/spunk
  rm -f /usr/bin/sudo
fi

CP_PATH=""
[ -x /bin/cp ] && CP_PATH="/bin/cp"
[ -x /usr/bin/cp ] && CP_PATH="/usr/bin/cp"

if [ -n "$CP_PATH" ]; then
  install -o root -g root -m 0755 "$CP_PATH" /bin/db
  rm -f "$CP_PATH"
fi

echo "[+] Hardening complete."
}

# =============================
# EXECUTION LOGIC
# =============================

run_local=false

if [ "${#HOSTS[@]}" -eq 0 ]; then
  run_local=true
fi

for h in "${HOSTS[@]}"; do
  if [ "$h" == "0.0.0.0" ]; then
    run_local=true
  fi
done

if $run_local; then
  echo "[*] Running locally..."
  if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Must be run as root locally"
    exit 1
  fi
  harden_system
  exit 0
fi

# =============================
# REMOTE EXECUTION
# =============================

for HOST in "${HOSTS[@]}"; do
  echo "[*] Connecting to $HOST..."

  sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no -p "$PORT" "$USERNAME@$HOST" <<EOF
echo "$PASSWORD" | sudo -S bash <<'ROOT_EOF'
$(declare -f harden_system)
harden_system
ROOT_EOF
EOF

  echo "[+] Finished $HOST"
done
