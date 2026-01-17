#!/bin/bash
echo "Showing all users with shell access"
awk -F: '{print $1, $7}' /etc/passwd | grep -v nologin

echo "List out the users with a UID, which allows root access"
grep 'x:0:' /etc/passwd
# or you can use cat /etc/passwd | cut -f1,3,4 -d":" | grep"0:0" | cut -f1 -d":" | awk '{print $1}'

echo "Listing out users in the root group"
grep -E '^(root|wheel|adm|admin):' /etc/group

echo "Showing the contents of /etc/sudoers, checking for users with sudo privileges"
sudo grep -E '\sALL[=(]' /etc/sudoers

# Searching for abuse of GFTObins
echo "List all programs that have a SUID bit that allows the program to be executed as root."
sudo find / -perm -04000

echo "Adding in the new Auditd rules file, look up how to use this or ask tyler :)."
sudo rm /etc/audit/auditd/rules.d
sudo mv auditd /etc/audit/auditd/rules.d
sudo systemctl restart auditd
sudo auditctl -R /etc/audit/auditd/rules.d

Echo "Listing to see if the new rules took effect"
sudo auditctl -l

# Tyler's notes: this one's kinda gross, but useful
echo "Shows every vulnerable file that any user can write to"
find / -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null | xargs ls -l

echo "Searching for any obvious gimmies using dpkg"
dpkg -l | grep -iE 'malicious|backdoor|suspicious|virus|evil|ev1l|bad'
