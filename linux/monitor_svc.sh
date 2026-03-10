#!/bin/bash

############################################
# BLUE TEAM SERVICE MONITOR + AUTO HEAL
############################################

CHECK_INTERVAL=30
BASE_DIR="/tmp/service_monitor"
HOSTNAME=$(hostname)
TIMESTAMP=$(date +"%F_%H-%M-%S")

mkdir -p "$BASE_DIR"

read -rp "Service name to monitor (systemctl): " SERVICE
read -rp "Full path to service config directory/file: " CONFIG_PATH
read -rp "Discord Webhook URL (leave blank to disable): " WEBHOOK

BASELINE="$BASE_DIR/${SERVICE}_baseline"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"

ORIG_PS1="$PS1"
STATE="UNKNOWN"
RESTART_ATTEMPTED=0

############################################
# CLEANUP
############################################
cleanup() {
    export PS1="$ORIG_PS1"
    echo -e "\n[+] Exiting. Prompt restored."
    exit 0
}
trap cleanup INT TERM

############################################
# DISCORD ALERT
############################################
send_discord() {
    [ -z "$WEBHOOK" ] && return
    local MSG="$1"
    curl -s -H "Content-Type: application/json" \
         -X POST \
         -d "{\"content\": \"$MSG\"}" \
         "$WEBHOOK" >/dev/null 2>&1
}

############################################
# INITIAL CONFIG BACKUP
############################################
echo "[*] Backing up baseline config..."
rsync -a --delete "$CONFIG_PATH" "$BASELINE" 2>/dev/null

############################################
# SERVICE CHECK
############################################
is_service_running() {
    systemctl is-active --quiet "$SERVICE"
}

############################################
# DIFF GENERATION
############################################
generate_diff() {
    diff -u "$BASELINE" "$CONFIG_PATH" 2>/dev/null
}

############################################
# RESTORE CONFIG
############################################
restore_config() {
    rsync -a --delete "$BASELINE/" "$CONFIG_PATH/" 2>/dev/null
}

############################################
# MAIN LOOP
############################################
echo "[*] Monitoring '$SERVICE' every ${CHECK_INTERVAL}s..."

while true; do
    if is_service_running; then
        if [ "$STATE" != "UP" ]; then
            MSG="**RECOVERY:** \`$SERVICE\` is UP on **$HOSTNAME**"
            wall "$MSG"
            send_discord "$MSG"
            export PS1="$ORIG_PS1"
            STATE="UP"
            RESTART_ATTEMPTED=0
        fi
    else
        if [ "$STATE" != "DOWN" ]; then
            STATE="DOWN"
            LOG_FILE="$LOG_DIR/${SERVICE}_$TIMESTAMP.log"

            MSG="**ALERT:** \`$SERVICE\` is DOWN on **$HOSTNAME**"
            wall "$MSG"
            send_discord "$MSG"

            echo "[*] Generating config diff..."
            DIFF_OUTPUT=$(generate_diff)
            echo "$DIFF_OUTPUT" > "$LOG_FILE"

            if [ -n "$DIFF_OUTPUT" ]; then
                DIFF_SNIPPET=$(echo "$DIFF_OUTPUT" | head -n 25)
                send_discord "**Config Diff Detected:**\n\`\`\`diff\n$DIFF_SNIPPET\n\`\`\`"
            fi

            echo "[*] Restoring baseline config..."
            restore_config

            if [ "$RESTART_ATTEMPTED" -eq 0 ]; then
                echo "[*] Attempting service restart..."
                systemctl restart "$SERVICE" 2>/dev/null
                sleep 5

                if is_service_running; then
                    send_discord "**AUTO-RESTART SUCCESS:** \`$SERVICE\` restarted cleanly."
                else
                    send_discord "**AUTO-RESTART FAILED:** \`$SERVICE\` still DOWN."
                fi

                RESTART_ATTEMPTED=1
            fi

            export PS1="\[\e[31m\][${SERVICE^^} DOWN] \[\e[0m\]$ORIG_PS1"
        fi
    fi

    sleep "$CHECK_INTERVAL"
done
