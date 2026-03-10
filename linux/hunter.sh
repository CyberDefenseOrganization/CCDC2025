#!/bin/bash

############################################
# Global Config
############################################
LOGDIR="/tmp/threathunt"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
mkdir -p "$LOGDIR"

exec > >(tee "$LOGDIR/threathunt_$DATE.log") 2>&1

echo "================================================="
echo " Linux Threat Hunting Script"
echo " Date: $(date)"
echo " Logs: $LOGDIR"
echo "================================================="

############################################
# Utility
############################################
sep() {
    echo -e "\n-----------------------------------------------\n"
}

############################################
# Golang Malware Detection
############################################
detect_golang() {
    sep
    echo "[+] Golang Binary Detection"

    find / -type f -executable -size +1M \
        ! -path "*snap*" ! -path "*docker*" ! -path "*container*" \
        2>/dev/null | while read -r f; do
            if strings "$f" 2>/dev/null | grep -q "go1\."; then
                echo "[GO] $f"
            fi
        done
}

############################################
# Rust Malware Detection
############################################
detect_rust() {
    sep
    echo "[+] Rust Binary Detection"

    find / -type f -executable -size +800k \
        ! -path "*snap*" ! -path "*docker*" ! -path "*container*" \
        2>/dev/null | while read -r f; do
            if strings "$f" 2>/dev/null | grep -E -q \
                'rust_eh_personality|core::panicking|std::rt|alloc::alloc|panic'; then
                echo "[RUST] $f"
            fi
        done
}

############################################
# Deleted-But-Running Malware
############################################
deleted_processes() {
    sep
    echo "[+] Deleted Running Processes"
    ls -l /proc/*/exe 2>/dev/null | grep "(deleted)"
}

############################################
# Unowned / Fake System Binaries
############################################
unowned_binaries() {
    sep
    echo "[+] Unowned / Fake System Binaries"

    PATHS="/bin /sbin /usr/bin /usr/sbin"

    if command -v dpkg &>/dev/null; then
        for f in $(find $PATHS -type f 2>/dev/null); do
            dpkg -S "$f" &>/dev/null || echo "[UNOWNED] $f"
        done
    elif command -v rpm &>/dev/null; then
        for f in $(find $PATHS -type f 2>/dev/null); do
            rpm -qf "$f" &>/dev/null || echo "[UNOWNED] $f"
        done
    else
        echo "No package manager detected."
    fi
}

############################################
# Recently Modified System Binaries
############################################
recent_system_changes() {
    sep
    echo "[+] Recently Modified System Binaries (7 days)"
    find /bin /sbin /usr/bin /usr/sbin -type f -mtime -7 2>/dev/null
}

############################################
# Writable + Executable Locations
############################################
writable_exec_dirs() {
    sep
    echo "[+] Executable Files in Writable Locations"
    find /tmp /var/tmp /dev/shm /run -type f -executable 2>/dev/null
}

############################################
# PATH Hijacking
############################################
path_hijack() {
    sep
    echo "[+] PATH Hijacking"
    echo "$PATH" | tr ':' '\n' | while read d; do
        [ -w "$d" ] && echo "[WRITABLE PATH] $d"
    done
}

############################################
# LD_PRELOAD / Loader Abuse
############################################
loader_abuse() {
    sep
    echo "[+] LD_PRELOAD / Loader Abuse"

    [ -f /etc/ld.so.preload ] && cat /etc/ld.so.preload
    env | grep -E 'LD_PRELOAD|LD_LIBRARY_PATH|PYTHONPATH|PERL5OPT'
}

############################################
# systemd Persistence
############################################
systemd_persistence() {
    sep
    echo "[+] systemd Persistence"

    find /etc/systemd/system -name "*.service" 2>/dev/null | while read svc; do
        echo "--- $svc ---"
        grep -E 'ExecStart|User|Group|Description' "$svc"
    done

    echo "[*] systemd Overrides"
    find /etc/systemd/system -path "*.service.d/*.conf" 2>/dev/null
}

############################################
# Cron Persistence (All Locations)
############################################
cron_persistence() {
    sep
    echo "[+] Cron Persistence"

    for u in $(cut -d: -f1 /etc/passwd); do
        crontab -l -u "$u" 2>/dev/null | sed "s/^/[${u}] /"
    done

    ls -la /etc/cron* /var/spool/cron 2>/dev/null
}

############################################
# User Startup Persistence
############################################
user_persistence() {
    sep
    echo "[+] User Startup Persistence"

    grep -R --line-number -E \
        'curl|wget|nc|bash -i|python|perl|sh -c' \
        /home/*/.bash* /home/*/.profile /home/*/.config/autostart \
        2>/dev/null
}

############################################
# SSH Backdoor Detection
############################################
ssh_abuse() {
    sep
    echo "[+] SSH Abuse"

    grep -E 'PermitUserEnvironment|AuthorizedKeysCommand|ForceCommand' \
        /etc/ssh/sshd_config 2>/dev/null

    grep -R "command=" /home/*/.ssh/authorized_keys 2>/dev/null
}

############################################
# PAM Backdoors
############################################
pam_abuse() {
    sep
    echo "[+] PAM Abuse"
    find /lib/security /usr/lib/security -type f -mtime -7 2>/dev/null
    grep -R "pam_exec" /etc/pam.d 2>/dev/null
}

############################################
# Capabilities Abuse
############################################
capabilities_abuse() {
    sep
    echo "[+] Linux Capabilities Abuse"
    getcap -r / 2>/dev/null
}

############################################
# SUID Binaries
############################################
suid_binaries() {
    sep
    echo "[+] SUID Binaries"
    find / -perm -4000 -type f 2>/dev/null
}

############################################
# Kernel / Rootkit Indicators
############################################
kernel_persistence() {
    sep
    echo "[+] Kernel Persistence"

    for t in /sys/module/*/taint; do
        grep -q "OE" "$t" && echo "[TAINTED] $t"
    done

    find /etc/systemd /etc/init.d -type f 2>/dev/null | \
        grep -E 'insmod|modprobe'
}

############################################
# Network Activity
############################################
network_activity() {
    sep
    echo "[+] Network Activity"
    ss -tulpan
}

############################################
# High-Entropy / Packed Binaries
############################################
packed_binaries() {
    sep
    echo "[+] Possible Packed Binaries (Entropy heuristic)"

    find / -type f -executable -size +1M \
        ! -path "*snap*" ! -path "*docker*" ! -path "*container*" \
        2>/dev/null | while read f; do
            entropy=$(ent "$f" 2>/dev/null | awk '/Entropy/ {print $3}')
            if [[ -n "$entropy" ]]; then
                awk "BEGIN {exit !($entropy > 7.5)}" && echo "[PACKED] $f ($entropy)"
            fi
        done
}

############################################
# Menu
############################################
echo "
1) Golang malware
2) Rust malware
3) Deleted running processes
4) Unowned binaries
5) Recent system changes
6) Writable exec locations
7) PATH hijacking
8) Loader abuse
9) systemd persistence
10) Cron persistence
11) User persistence
12) SSH abuse
13) PAM abuse
14) Capabilities abuse
15) SUID binaries
16) Kernel persistence
17) Network activity
18) Packed binaries
19) ALL CHECKS
"

read -rp "Select option: " opt

case $opt in
1) detect_golang ;;
2) detect_rust ;;
3) deleted_processes ;;
4) unowned_binaries ;;
5) recent_system_changes ;;
6) writable_exec_dirs ;;
7) path_hijack ;;
8) loader_abuse ;;
9) systemd_persistence ;;
10) cron_persistence ;;
11) user_persistence ;;
12) ssh_abuse ;;
13) pam_abuse ;;
14) capabilities_abuse ;;
15) suid_binaries ;;
16) kernel_persistence ;;
17) network_activity ;;
18) packed_binaries ;;
19)
    detect_golang
    detect_rust
    deleted_processes
    unowned_binaries
    recent_system_changes
    writable_exec_dirs
    path_hijack
    loader_abuse
    systemd_persistence
    cron_persistence
    user_persistence
    ssh_abuse
    pam_abuse
    capabilities_abuse
    suid_binaries
    kernel_persistence
    network_activity
    packed_binaries
    ;;
*)
    echo "Invalid selection"
esac

echo -e "\nThreat Hunting Completed"
