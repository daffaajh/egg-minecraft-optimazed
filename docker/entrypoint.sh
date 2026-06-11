#!/bin/bash
cd "${SERVER_DIR:-/home/container}" || exit 1

YURACLOUD_DIR="$HOME/YuraCloud/data"
AUTORESTART_FILE="$YURACLOUD_DIR/autorestart.txt"
STATUS_FILE="$YURACLOUD_DIR/autorestart_status.txt"
SERVER_STATE_FILE="$YURACLOUD_DIR/server_state.flag"

# Buat direktori YuraCloud/data kalau belum ada
mkdir -p "$YURACLOUD_DIR"

# Generate random restart time antara 00:00 - 03:00 (hanya sekali saat pertama install)
if [ ! -f "$AUTORESTART_FILE" ]; then
    RANDOM_HOUR=$(shuf -i 0-2 -n 1)
    RANDOM_MINUTE=$(shuf -i 0-59 -n 1)
    RESTART_TIME=$(printf "%02d:%02d" $RANDOM_HOUR $RANDOM_MINUTE)
    echo "Server akan restart terus-menerus pada jam $RESTART_TIME WIB" > "$AUTORESTART_FILE"
    echo "inactive" > "$STATUS_FILE"
    echo "[$RESTART_TIME] Auto-restart schedule generated" >> "$YURACLOUD_DIR/restart.log"
else
    # Baca waktu restart yang sudah ada
    RESTART_TIME=$(grep -oP '\d{2}:\d{2}' "$AUTORESTART_FILE" | head -1)
fi

# Set status jadi active karena server starting
echo "active" > "$STATUS_FILE"

# ==========================================
# SWAP OPTIMIZATION - Kurangi Lag saat di Swap
# ==========================================

# Tuning swap behavior (kalau container punya akses ke sysctl)
if [ -w /proc/sys/vm/swappiness ] 2>/dev/null; then
    echo 10 > /proc/sys/vm/swappiness
    echo "[SWAP] Set swappiness=10 (minimal swap usage)" >> "$YURACLOUD_DIR/startup.log"
fi

if [ -w /proc/sys/vm/vfs_cache_pressure ] 2>/dev/null; then
    echo 50 > /proc/sys/vm/vfs_cache_pressure
    echo "[SWAP] Set vfs_cache_pressure=50" >> "$YURACLOUD_DIR/startup.log"
fi

if [ -w /sys/kernel/mm/transparent_hugepage/defrag ] 2>/dev/null; then
    echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag
    echo "[SWAP] Set THP defrag=defer+madvise" >> "$YURACLOUD_DIR/startup.log"
fi

# Java-specific swap optimization flags
SWAP_OPTIMIZE_FLAGS=""
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))

if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    SWAP_OPTIMIZE_FLAGS="-XX:+UseZGC -XX:+ZGenerational -XX:SoftMaxHeapSize=80% -XX:ZCollectionInterval=5 -XX:ZFragmentationLimit=5 -XX:+UseTransparentHugePages -XX:+AlwaysPreTouch"
    echo "[SWAP] Low memory detected ($TOTAL_MEM_MB MB). Applying aggressive swap optimization." >> "$YURACLOUD_DIR/startup.log"
else
    SWAP_OPTIMIZE_FLAGS="-XX:+UseTransparentHugePages -XX:+AlwaysPreTouch"
    echo "[SWAP] Normal memory ($TOTAL_MEM_MB MB). Applying standard optimization." >> "$YURACLOUD_DIR/startup.log"
fi

# ==========================================
# STARTUP INFO
# ==========================================

echo "=========================================="
echo "YuraCloud Optix Container"
echo "=========================================="
echo "Timezone: Asia/Jakarta (WIB)"
echo "Current Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
java -version 2>&1 | head -1
echo ""
echo "Memory: ${TOTAL_MEM_MB}MB total"
echo "Swap Optimization: ENABLED"
echo ""
cat "$AUTORESTART_FILE"
echo "Auto-Restart Status: ACTIVE"
echo "=========================================="
echo ""

# Jalankan autorestart monitor di background
/autorestart.sh "$RESTART_TIME" "$SERVER_STATE_FILE" "$STATUS_FILE" &

# Tandai bahwa server sedang running
touch "$SERVER_STATE_FILE"

# Inject swap optimization flags
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

if [[ "$MODIFIED_STARTUP" == *"java"* ]]; then
    MODIFIED_STARTUP=$(echo "$MODIFIED_STARTUP" | sed "s/java /java $SWAP_OPTIMIZE_FLAGS /")
    echo "[SWAP] Injected optimization flags into startup" >> "$YURACLOUD_DIR/startup.log"
fi

echo "[STARTUP] Executing: $MODIFIED_STARTUP" >> "$YURACLOUD_DIR/startup.log"
eval "${MODIFIED_STARTUP}"

# Kalau server mati, set status jadi inactive dan hapus state flag
echo "inactive" > "$STATUS_FILE"
rm -f "$SERVER_STATE_FILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server stopped. Auto-restart set to inactive." >> "$YURACLOUD_DIR/restart.log"
