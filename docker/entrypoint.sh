#!/bin/bash
cd "${SERVER_DIR:-/home/container}" || exit 1

YURACLOUD_DIR="$HOME/YuraCloud/data"
AUTORESTART_FILE="$YURACLOUD_DIR/autorestart.txt"
STATUS_FILE="$YURACLOUD_DIR/autorestart_status.txt"
SERVER_STATE_FILE="$YURACLOUD_DIR/server_state.flag"
CMD_FIFO="/tmp/minecraft-cmd.fifo"

# Buat direktori YuraCloud/data kalau belum ada
mkdir -p "$YURACLOUD_DIR"

# Auto-delete logs older than 2 days
find "$YURACLOUD_DIR" -name "*.log" -type f -mtime +2 -delete 2>/dev/null

# Handle Auto-Restart Time (manual atau auto)
RESTART_TIME=""
if [ ! -f "$AUTORESTART_FILE" ]; then
    # First time setup
    if [ "${AUTO_RESTART_TIME}" == "auto" ] || [ -z "${AUTO_RESTART_TIME}" ]; then
        # Generate random time antara 00:00 - 02:59 (consistent with install script)
        RANDOM_HOUR=$(shuf -i 0-2 -n 1)
        RANDOM_MINUTE=$(shuf -i 0-59 -n 1)
        RESTART_TIME=$(printf "%02d:%02d" $RANDOM_HOUR $RANDOM_MINUTE)
    else
        # Use admin-defined time
        RESTART_TIME="${AUTO_RESTART_TIME}"
    fi
    echo "Server akan restart terus-menerus pada jam $RESTART_TIME WIB" > "$AUTORESTART_FILE"
    echo "inactive" > "$STATUS_FILE"
    echo "[$(TZ=Asia/Jakarta date '+%Y-%m-%d %H:%M:%S')] Auto-restart schedule set to $RESTART_TIME WIB" >> "$YURACLOUD_DIR/restart.log"
else
    # Baca waktu restart yang sudah ada
    RESTART_TIME=$(grep -oP '\d{2}:\d{2}' "$AUTORESTART_FILE" | head -1)
fi

# Set status jadi active karena server starting
echo "active" > "$STATUS_FILE"

# ==========================================
# SWAP OPTIMIZATION
# ==========================================

if [ -w /proc/sys/vm/swappiness ] 2>/dev/null; then
    echo 10 > /proc/sys/vm/swappiness
fi

if [ -w /proc/sys/vm/vfs_cache_pressure ] 2>/dev/null; then
    echo 50 > /proc/sys/vm/vfs_cache_pressure
fi

if [ -w /sys/kernel/mm/transparent_hugepage/defrag ] 2>/dev/null; then
    echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag
fi

# Java-specific memory tuning (compatible with G1GC from MC_STARTUP, all Java versions)
MEMORY_TUNING_FLAGS=""
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))

if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    # Low-memory tuning: reduce GC overhead without replacing G1GC
    MEMORY_TUNING_FLAGS="-XX:G1HeapRegionSize=4M -XX:InitiatingHeapOccupancyPercent=30 -XX:G1HeapWastePercent=8 -XX:SoftRefLRUPolicyMSPerMB=0"
fi

# ==========================================
# STARTUP INFO
# ==========================================

echo "=========================================="
echo "       YuraCloud Optix Container"
echo "=========================================="
echo ""
echo "Timezone: Asia/Jakarta (WIB)"
echo "Local Time: $(TZ=Asia/Jakarta date '+%Y-%m-%d %H:%M:%S')"
echo ""
cat "$AUTORESTART_FILE"
echo ""
echo "=========================================="

# ==========================================
# COMMAND FIFO (for restart warnings from autorestart.sh)
# ==========================================
# Create named pipe for sending commands to server stdin
rm -f "$CMD_FIFO"
mkfifo "$CMD_FIFO"

# Bridge Pterodactyl console input to FIFO (so panel console still works)
cat <&0 >> "$CMD_FIFO" &

# Jalankan autorestart monitor di background
/autorestart.sh "$RESTART_TIME" "$SERVER_STATE_FILE" "$STATUS_FILE" "$CMD_FIFO" &

# Tandai bahwa server sedang running
touch "$SERVER_STATE_FILE"

# Inject memory tuning flags
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

if [[ "$MODIFIED_STARTUP" == *"java"* ]] && [ -n "$MEMORY_TUNING_FLAGS" ]; then
    MODIFIED_STARTUP=$(echo "$MODIFIED_STARTUP" | sed "s/java /java $MEMORY_TUNING_FLAGS /")
fi

# Execute startup - server reads commands from FIFO (enables restart warnings)
eval "${MODIFIED_STARTUP}" < "$CMD_FIFO" 2>&1 | grep -v -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}\+[0-9]{4}\]\['

# Kalau server mati, set status jadi inactive dan hapus state flag
echo "inactive" > "$STATUS_FILE"
rm -f "$SERVER_STATE_FILE"
rm -f "$CMD_FIFO"
