#!/usr/bin/env bash
#
# Launch Claude Code with remote execution and filesystem
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

# Ensure remote filesystem is mounted
"$SCRIPT_DIR/mount-remote.sh"

# Launch Claude with remote shell
cd "$LOCAL_MOUNT"
SHELL="$SCRIPT_DIR/remote-shell.sh" exec claude "$@"
