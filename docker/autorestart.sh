#!/bin/bash

RESTART_TIME="$1"
SERVER_STATE_FILE="$2"
STATUS_FILE="$3"
YURACLOUD_DIR="$HOME/YuraCloud/data"
SERVER_DIR="${SERVER_DIR:-/home/container}"
TZ="Asia/Jakarta"

if [ -z "$RESTART_TIME" ]; then
    exit 0
fi

RESTART_HOUR_STR=$(echo "$RESTART_TIME" | cut -d: -f1)
RESTART_MINUTE_STR=$(echo "$RESTART_TIME" | cut -d: -f2)

# Remove leading zeros for arithmetic (avoid octal interpretation)
RESTART_HOUR=$((10#${RESTART_HOUR_STR}))
RESTART_MINUTE=$((10#${RESTART_MINUTE_STR}))

echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Auto-restart monitor started. Scheduled: $RESTART_TIME WIB" >> "$YURACLOUD_DIR/restart.log"

# ==========================================
# RCON Helper Function
# ==========================================

send_rcon() {
    local cmd="$1"
    if [ -n "$RCON_PASS" ] && [ -n "$RCON_PORT" ] && command -v rcon-cli &>/dev/null; then
        rcon-cli --host 127.0.0.1 --port "$RCON_PORT" --password "$RCON_PASS" "$cmd" >/dev/null 2>&1
    fi
}

# Read RCON config from server.properties
# RCON port is derived from server port (server_port + 1) since Pterodactyl uses random ports
get_rcon_config() {
    local PROPS="$SERVER_DIR/server.properties"
    if [ -f "$PROPS" ]; then
        RCON_PASS=$(grep -E '^rcon\.password=' "$PROPS" | cut -d= -f2- | tr -d '[:space:]')
        # Derive RCON port from actual server port (works with any Pterodactyl random port)
        local SERVER_PORT=$(grep -E '^server-port=' "$PROPS" | cut -d= -f2 | tr -d '[:space:]')
        if [ -n "$SERVER_PORT" ]; then
            RCON_PORT=$((SERVER_PORT + 1))
        else
            RCON_PORT=$(grep -E '^rcon\.port=' "$PROPS" | cut -d= -f2 | tr -d '[:space:]')
        fi
    fi
    RCON_PORT="${RCON_PORT:-25575}"
}

# ==========================================
# Warning Schedule
# ==========================================
# Warn players at: 5 min, 3 min, 1 min, 10 sec countdown, then restart

WARNING_MINUTES=(5 3 1)

while true; do
    sleep 60

    # Cek apakah server masih running (cek state flag)
    if [ ! -f "$SERVER_STATE_FILE" ]; then
        echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Server stopped. Auto-restart disabled." >> "$YURACLOUD_DIR/restart.log"
        echo "inactive" > "$STATUS_FILE"
        exit 0
    fi

    # Get current time with explicit timezone
    CURRENT_HOUR=$((10#$(TZ=$TZ date '+%H')))
    CURRENT_MINUTE=$((10#$(TZ=$TZ date '+%M')))

    # Calculate minutes until restart
    CURRENT_TOTAL=$((CURRENT_HOUR * 60 + CURRENT_MINUTE))
    RESTART_TOTAL=$((RESTART_HOUR * 60 + RESTART_MINUTE))
    MINUTES_UNTIL=$((RESTART_TOTAL - CURRENT_TOTAL))

    # Handle next-day wrap
    if [ "$MINUTES_UNTIL" -lt 0 ]; then
        MINUTES_UNTIL=$((MINUTES_UNTIL + 1440))
    fi

    # Send minute-level warnings
    for WARN_MIN in "${WARNING_MINUTES[@]}"; do
        if [ "$MINUTES_UNTIL" -eq "$WARN_MIN" ]; then
            get_rcon_config
            send_rcon "say [ YuraCloud ] Server akan restart dalam ${WARN_MIN} menit!"
            echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Warning sent: ${WARN_MIN} minutes until restart" >> "$YURACLOUD_DIR/restart.log"
            break
        fi
    done

    # Final 60-second countdown when 1 minute or less remaining
    if [ "$MINUTES_UNTIL" -le 1 ] && [ "$MINUTES_UNTIL" -ge 0 ]; then
        # Sleep until exactly 10 seconds before restart
        CURRENT_SEC=$((10#$(TZ=$TZ date '+%S')))
        SECONDS_LEFT=$(( (MINUTES_UNTIL * 60) + (60 - CURRENT_SEC) ))
        SLEEP_UNTIL_10=$((SECONDS_LEFT - 10))

        if [ "$SLEEP_UNTIL_10" -gt 0 ]; then
            sleep "$SLEEP_UNTIL_10"
        fi

        # Verify server is still running
        if [ ! -f "$SERVER_STATE_FILE" ]; then
            exit 0
        fi

        # Re-fetch RCON config for countdown
        get_rcon_config

        # 10-second countdown
        for i in $(seq 10 -1 1); do
            send_rcon "say [ YuraCloud ] Server akan restart dalam ${i} detik!"
            echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Countdown: ${i} seconds" >> "$YURACLOUD_DIR/restart.log"
            sleep 1

            # Verify server is still running each second
            if [ ! -f "$SERVER_STATE_FILE" ]; then
                exit 0
            fi
        done

        # Final restart command
        send_rcon "say [ YuraCloud ] Server sedang restart..."
        echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Triggering scheduled restart..." >> "$YURACLOUD_DIR/restart.log"

        # Cari PID Java process dan kill gracefully
        JAVA_PID=$(pgrep -f "java.*jar" | head -1)
        if [ -n "$JAVA_PID" ]; then
            kill -TERM "$JAVA_PID"
            echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Sent SIGTERM to PID $JAVA_PID" >> "$YURACLOUD_DIR/restart.log"
        fi

        # Tunggu 2 menit sebelum cek lagi (avoid multiple restart di menit yang sama)
        sleep 120
    fi
done
