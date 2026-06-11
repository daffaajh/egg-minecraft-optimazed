#!/bin/bash

RESTART_TIME="$1"
SERVER_STATE_FILE="$2"
STATUS_FILE="$3"
YURACLOUD_DIR="$HOME/YuraCloud/data"

if [ -z "$RESTART_TIME" ]; then
    exit 0
fi

RESTART_HOUR=$(echo "$RESTART_TIME" | cut -d: -f1)
RESTART_MINUTE=$(echo "$RESTART_TIME" | cut -d: -f2)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-restart monitor started. Scheduled: $RESTART_TIME WIB" >> "$YURACLOUD_DIR/restart.log"

while true; do
    sleep 60
    
    # Cek apakah server masih running (cek state flag)
    if [ ! -f "$SERVER_STATE_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server stopped. Auto-restart disabled." >> "$YURACLOUD_DIR/restart.log"
        echo "inactive" > "$STATUS_FILE"
        exit 0
    fi
    
    CURRENT_HOUR=$(date +%H)
    CURRENT_MINUTE=$(date +%M)
    
    # Cek apakah sudah waktunya restart
    if [ "$CURRENT_HOUR" == "$RESTART_HOUR" ] && [ "$CURRENT_MINUTE" == "$RESTART_MINUTE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Triggering scheduled restart..." >> "$YURACLOUD_DIR/restart.log"
        
        # Cari PID Java process dan kill gracefully
        JAVA_PID=$(pgrep -f "java.*jar" | head -1)
        if [ -n "$JAVA_PID" ]; then
            kill -TERM "$JAVA_PID"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sent SIGTERM to PID $JAVA_PID" >> "$YURACLOUD_DIR/restart.log"
        fi
        
        # Tunggu 2 menit sebelum cek lagi (avoid multiple restart di menit yang sama)
        sleep 120
    fi
done
