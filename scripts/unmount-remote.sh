#!/usr/bin/env bash
#
# Unmount remote filesystem
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

if mount | grep -q "$LOCAL_MOUNT"; then
    umount "$LOCAL_MOUNT" 2>/dev/null || diskutil unmount force "$LOCAL_MOUNT"
    echo "✓ Unmounted $LOCAL_MOUNT"
else
    echo "○ Not mounted"
fi
