#!/bin/bash

RESTART_TIME="$1"
SERVER_STATE_FILE="$2"
STATUS_FILE="$3"
CMD_FIFO="$4"
YURACLOUD_DIR="$HOME/YuraCloud/data"
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
# Command Helper (writes to server stdin via FIFO)
# ==========================================

send_cmd() {
    local cmd="$1"
    if [ -n "$CMD_FIFO" ] && [ -p "$CMD_FIFO" ]; then
        echo "$cmd" >> "$CMD_FIFO"
    fi
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
            send_cmd "say [ YuraCloud ] Server akan restart dalam ${WARN_MIN} menit!"
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

        # 10-second countdown
        for i in $(seq 10 -1 1); do
            send_cmd "say [ YuraCloud ] Server akan restart dalam ${i} detik!"
            echo "[$(TZ=$TZ date '+%Y-%m-%d %H:%M:%S')] Countdown: ${i} seconds" >> "$YURACLOUD_DIR/restart.log"
            sleep 1

            # Verify server is still running each second
            if [ ! -f "$SERVER_STATE_FILE" ]; then
                exit 0
            fi
        done

        # Final restart command
        send_cmd "say [ YuraCloud ] Server sedang restart..."
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
