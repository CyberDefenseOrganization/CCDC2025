#!/bin/bash

OUTPUT_DIR="/opt/enum"
SYS_FILE="$OUTPUT_DIR/sys-stats.txt"
NET_FILE="$OUTPUT_DIR/net-info.txt"

# Ensure directory exists
mkdir -p "$OUTPUT_DIR"

# Collect system stats
{
echo "===== OS INFO ====="
cat /etc/os-release
echo

echo "===== CPU INFO ====="
lscpu | head -n 18
echo

echo "===== MEMORY ====="
free -h
} > "$SYS_FILE"

# Collect network info
{
echo "===== NETWORK INTERFACES ====="
ip a
} > "$NET_FILE"

# Print reminder of file locations
echo
echo "System enumeration complete."
echo "System stats saved to: $SYS_FILE"
echo "Network info saved to: $NET_FILE"
