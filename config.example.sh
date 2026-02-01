# Claude Remote Configuration
# Copy this file to config.sh and edit with your values

# SSH connection to remote machine
REMOTE_HOST="ubuntu@your-ec2-instance.amazonaws.com"

# Directory on remote machine where commands will execute
REMOTE_DIR="/home/ubuntu/Projects"

# Local mount point for remote filesystem
LOCAL_MOUNT="$HOME/Projects/remote"
