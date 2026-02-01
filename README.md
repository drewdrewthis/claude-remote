# Claude Remote

Run Claude Code locally with the UI on your machine, but execute all commands and access files on a remote server.

**Why?** Claude Code can be CPU-intensive (TypeScript compilation, tests, file operations). This setup lets you:
- Keep your local machine fast and responsive
- Use a powerful remote server (EC2, etc.) for heavy lifting
- Maintain low-latency typing since the Claude UI runs locally

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Your Mac (Local)                            │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────────────┐    │
│  │ Claude Code  │───▶│ remote-shell │───▶│ SSH ControlMaster  │    │
│  │   (UI/TUI)   │    │   wrapper    │    │ (persistent conn)  │    │
│  └──────────────┘    └──────────────┘    └─────────┬──────────┘    │
│         │                                          │                │
│         ▼                                          │                │
│  ┌──────────────┐                                  │                │
│  │ ~/Projects/  │◀── SSHFS mount ──────────────────┼────────┐      │
│  │   remote/    │                                  │        │      │
│  └──────────────┘                                  │        │      │
└────────────────────────────────────────────────────┼────────┼──────┘
                                                     │        │
                                                     ▼        │
┌────────────────────────────────────────────────────────────────────┐
│                      Remote Server (EC2)                           │
│  ┌──────────────┐    ┌──────────────────────────────────────┐     │
│  │   SSH        │    │  /home/ubuntu/Projects/               │     │
│  │   Server     │───▶│  (your actual files & execution)     │     │
│  └──────────────┘    └──────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────┘
```

### How it works

1. **Shell Interception**: Claude Code uses `$SHELL` to execute commands. We provide a custom shell wrapper that:
   - Intercepts all commands Claude tries to run
   - Forwards them via SSH to the remote server
   - Loads the remote user's full profile (nvm, pyenv, etc.)
   - Returns output and exit codes transparently

2. **Filesystem Access**: SSHFS mounts the remote filesystem locally, so Claude's file tools (Read, Write, Edit, Glob, Grep) work transparently on remote files.

3. **SSH Multiplexing**: Uses SSH ControlMaster for persistent connections, avoiding SSH handshake overhead on every command.

## Requirements

- macOS (tested on macOS 15+)
- [Claude Code](https://claude.ai/code) installed
- SSH access to a remote server (with key-based auth)
- FUSE-T and sshfs for filesystem mounting

## Installation

### 1. Install dependencies

```bash
# Install FUSE-T (modern FUSE for macOS, no kernel extension)
brew install --cask fuse-t
brew install macos-fuse-t/cask/fuse-t-sshfs
```

### 2. Clone and setup

```bash
git clone https://github.com/langwatch/claude-remote.git ~/Projects/claude-remote
cd ~/Projects/claude-remote
./setup.sh
```

The setup script will:
- Prompt for your remote server details
- Create symlinks in `~/bin`
- Test your SSH connection

### 3. Ensure SSH key auth works

```bash
# If you haven't set up SSH keys
ssh-copy-id ubuntu@your-server.com
```

## Usage

```bash
# Launch Claude with remote execution
claude-remote

# Or manually:
mount-remote           # Mount remote filesystem
unmount-remote         # Unmount when done
```

Once running, all Claude commands execute on the remote server:

```
❯ uname -a
Linux ip-10-0-3-248 6.14.0-1018-aws ... aarch64 GNU/Linux

❯ which pnpm python3
/home/ubuntu/.nvm/versions/node/v24.13.0/bin/pnpm
/usr/bin/python3
```

## Configuration

Edit `config.sh` (created by setup.sh):

```bash
# SSH connection to remote machine
REMOTE_HOST="ubuntu@your-ec2-instance.amazonaws.com"

# Directory on remote machine where commands will execute
REMOTE_DIR="/home/ubuntu/Projects"

# Local mount point for remote filesystem
LOCAL_MOUNT="$HOME/Projects/remote"
```

## Tips

### Port Forwarding

If your remote server runs services (dev servers, databases, etc.), forward ports to access them locally:

```bash
# Forward a single port (e.g., Next.js dev server on 3000)
ssh -N -L 3000:localhost:3000 ubuntu@your-server.com

# Forward multiple ports
ssh -N -L 3000:localhost:3000 -L 5432:localhost:5432 ubuntu@your-server.com

# Run in background
ssh -fN -L 3000:localhost:3000 ubuntu@your-server.com
```

Now `http://localhost:3000` on your Mac connects to the remote server.

## Troubleshooting

### Commands not finding binaries (pnpm, node, etc.)

The remote shell runs with `-i` (interactive) to load your full profile. If commands still aren't found:

1. Check your remote `~/.bashrc` loads the necessary paths
2. Verify: `ssh your-server "bash -i -c 'which pnpm'"`

### Mount issues

```bash
# Force unmount if stuck
unmount-remote
# or
diskutil unmount force ~/Projects/remote

# Remount
mount-remote
```

### SSH connection issues

```bash
# Test SSH
ssh -v your-server "echo ok"

# Clear SSH control socket if stuck
rm /tmp/ssh-claude-*
```

### Slow performance

1. Ensure SSH ControlMaster is working (connections should be instant after first one)
2. For large projects, consider excluding `node_modules` from SSHFS with `-o exclude`

## How the shell wrapper works

Claude Code invokes the shell like: `$SHELL -c -l "command"`

Our wrapper (`scripts/remote-shell.sh`):
1. Parses the flags and extracts the command
2. Handles Claude's working directory tracking (`pwd -P >| /tmp/...`)
3. Forwards the command via SSH with `bash -i` to load the full profile
4. Filters harmless TTY warnings
5. Preserves the exit code

## Contributing

PRs welcome! Some ideas:
- [ ] Support for Linux local machines
- [ ] Docker-based remote execution option
- [ ] Automatic reconnection handling
- [ ] Exclude patterns for SSHFS mount

## License

MIT
