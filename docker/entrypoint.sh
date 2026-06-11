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

if [ -w /proc/sys/vm/swappiness ] 2>/dev/null; then
    echo 10 > /proc/sys/vm/swappiness
fi

if [ -w /proc/sys/vm/vfs_cache_pressure ] 2>/dev/null; then
    echo 50 > /proc/sys/vm/vfs_cache_pressure
fi

if [ -w /sys/kernel/mm/transparent_hugepage/defrag ] 2>/dev/null; then
    echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag
fi

# Java-specific swap optimization flags
SWAP_OPTIMIZE_FLAGS=""
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))

if [ "$TOTAL_MEM_MB" -lt 2048 ]; then
    SWAP_OPTIMIZE_FLAGS="-XX:+UseZGC -XX:+ZGenerational -XX:SoftMaxHeapSize=80% -XX:ZCollectionInterval=5 -XX:ZFragmentationLimit=5 -XX:+AlwaysPreTouch"
else
    SWAP_OPTIMIZE_FLAGS="-XX:+AlwaysPreTouch"
fi

# ==========================================
# STARTUP INFO (Simplified - No Verbose Logs)
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

# Jalankan autorestart monitor di background
/autorestart.sh "$RESTART_TIME" "$SERVER_STATE_FILE" "$STATUS_FILE" &

# Tandai bahwa server sedang running
touch "$SERVER_STATE_FILE"

# Inject swap optimization flags
MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')

if [[ "$MODIFIED_STARTUP" == *"java"* ]]; then
    MODIFIED_STARTUP=$(echo "$MODIFIED_STARTUP" | sed "s/java /java $SWAP_OPTIMIZE_FLAGS /")
fi

# Execute startup dengan suppress verbose GC logs
eval "${MODIFIED_STARTUP}" 2>&1 | grep -v -E '^\[.*\]\[.*\]|CardTable|Compressed|Metaspace|garbage-first|CDS archive'

# Kalau server mati, set status jadi inactive dan hapus state flag
echo "inactive" > "$STATUS_FILE"
rm -f "$SERVER_STATE_FILE"
