#!/usr/bin/env bash
#
# Mount remote filesystem via SSHFS
#

# Resolve symlinks to find the real script directory
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
source "$SCRIPT_DIR/../config.sh" 2>/dev/null || {
    echo "Error: config.sh not found. Run ./setup.sh first." >&2
    exit 1
}

# Check if already mounted
if mount | grep -q "$LOCAL_MOUNT"; then
    echo "✓ Already mounted at $LOCAL_MOUNT"
    exit 0
fi

# Create mount point if needed
mkdir -p "$LOCAL_MOUNT"

# Mount with aggressive caching for better performance
sshfs "$REMOTE_HOST:$REMOTE_DIR" "$LOCAL_MOUNT" \
    -o reconnect \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o defer_permissions \
    -o volname=claude-remote \
    -o cache=yes \
    -o cache_timeout=600 \
    -o attr_timeout=600 \
    -o entry_timeout=600 \
    -o max_readahead=131072 \
    -o Compression=no

if [ $? -eq 0 ]; then
    echo "✓ Mounted $REMOTE_HOST:$REMOTE_DIR at $LOCAL_MOUNT"
else
    echo "✗ Mount failed"
    exit 1
fi
