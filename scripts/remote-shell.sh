#!/usr/bin/env bash
#
# Remote shell wrapper for Claude Code
# Intercepts shell commands and executes them on the remote machine
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

SSH_OPTS="-o ControlMaster=auto -o ControlPath=/tmp/ssh-claude-%r@%h:%p -o ControlPersist=600"

# Parse flags - Claude Code sends: -c -l "command"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c)
            shift
            ;;
        -l|-i)
            # Skip login/interactive flags
            shift
            ;;
        *)
            # This is the command
            cmd="$1"
            break
            ;;
    esac
done

if [[ -n "$cmd" ]]; then
    # Claude Code appends: && pwd -P >| /var/folders/.../claude-xxx-cwd
    # Extract it and run locally after SSH completes
    pwd_suffix=""
    if [[ "$cmd" =~ (.*)(\&\&\ pwd\ -P\ \>\|\ [^[:space:]]+)$ ]]; then
        cmd="${BASH_REMATCH[1]}"
        pwd_suffix="${BASH_REMATCH[2]}"
    fi

    # Run the actual command remotely with interactive shell (-i) to load full profile
    # Filter out harmless TTY warnings from bash -i, preserve exit code with PIPESTATUS
    /usr/bin/ssh $SSH_OPTS "$REMOTE_HOST" "cd $REMOTE_DIR && /bin/bash -i -c $(printf '%q' "$cmd")" 2>&1 | grep -v "^bash: cannot set terminal process group\|^bash: no job control\|^manpath:"
    exit_code=${PIPESTATUS[0]}

    # Run the pwd redirect locally if it was present
    if [[ -n "$pwd_suffix" ]]; then
        eval "$pwd_suffix" 2>/dev/null || true
    fi

    exit $exit_code
else
    # No command, interactive login shell
    /usr/bin/ssh $SSH_OPTS -t "$REMOTE_HOST" "cd $REMOTE_DIR && /bin/bash -l"
fi
