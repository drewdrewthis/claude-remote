#!/usr/bin/env bash
#
# Start Mutagen sync session
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

# Ensure daemon is running
mutagen daemon start 2>/dev/null

# Check if sync already exists
if mutagen sync list 2>/dev/null | grep -q "claude-remote"; then
    echo "✓ Sync session 'claude-remote' already exists"
    mutagen sync list --label-selector=name=claude-remote
    exit 0
fi

# Create local directory if needed
mkdir -p "$LOCAL_MOUNT"

# Create sync session with ignores
echo "Creating Mutagen sync session..."
mutagen sync create "$LOCAL_MOUNT" "$REMOTE_HOST:$REMOTE_DIR" \
    --name=claude-remote \
    --label=name=claude-remote \
    --ignore="node_modules" \
    --ignore=".venv" \
    --ignore=".cache" \
    --ignore="dist" \
    --ignore=".next*" \
    --ignore="__pycache__" \
    --ignore=".pytest_cache" \
    --ignore=".mypy_cache" \
    --ignore=".turbo" \
    --ignore="*.pyc" \
    --ignore=".DS_Store" \
    --ignore="coverage" \
    --ignore=".nyc_output" \
    --ignore="target" \
    --ignore="build" \
    --sync-mode=two-way-resolved \
    --default-file-mode=0644 \
    --default-directory-mode=0755

if [ $? -eq 0 ]; then
    echo "✓ Sync session created"
    echo "Waiting for initial sync..."
    mutagen sync flush --label-selector=name=claude-remote
    echo "✓ Initial sync complete"
else
    echo "✗ Failed to create sync session"
    exit 1
fi
