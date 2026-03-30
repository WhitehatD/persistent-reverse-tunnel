#!/bin/bash
## Sets up session persistence on the VPS for mobile connections.
## Usage: ssh root@your-vps 'bash -s' < setup-phone-session.sh
##
## Prerequisites:
##   - setup-vps.sh already ran
##   - Tunnel keypair exists (~/.ssh/id_tunnel + id_tunnel.pub)
##   - Reverse tunnel is running (laptop → VPS)

set -euo pipefail

echo "Setting up session persistence..."

# Install tmux
if ! command -v tmux &>/dev/null; then
    echo "Installing tmux..."
    apt-get update -qq && apt-get install -y -qq tmux
else
    echo "tmux already installed: $(tmux -V)"
fi

# Install session script
SCRIPT="/root/phone-session.sh"
cat > "$SCRIPT" <<'SCRIPT_EOF'
#!/bin/bash
SESSION="laptop"

if tmux has-session -t "$SESSION" 2>/dev/null; then
    exec tmux attach-session -d -t "$SESSION"
fi

exec tmux new-session -s "$SESSION" 'while true; do
    ssh -p 2222 -i /root/.ssh/id_tunnel \
        -o ServerAliveInterval=15 \
        -o ServerAliveCountMax=3 \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        alexc@localhost
    echo ""
    echo "[Session ended — reconnecting in 3s. Press Ctrl+C to stop]"
    sleep 3
done'
SCRIPT_EOF
chmod +x "$SCRIPT"

# Configure tmux
cat > /root/.tmux.conf <<'TMUX_EOF'
set -g history-limit 50000
set -g mouse on
set -sg escape-time 10
set -g default-terminal "screen-256color"
set -g allow-rename off
set -g automatic-rename off
set -g status-style "bg=#1a1a2e fg=#e0e0e0"
set -g status-left "#[fg=#00d4ff][tmux] "
set -g status-right "#[fg=#888888]%H:%M "
TMUX_EOF

# Register tunnel key with forced command
TUNNEL_PUB=$(cat /root/.ssh/id_tunnel.pub 2>/dev/null || true)
if [ -z "$TUNNEL_PUB" ]; then
    echo "ERROR: /root/.ssh/id_tunnel.pub not found."
    echo "       Generate it first: ssh-keygen -t ed25519 -f ~/.ssh/id_tunnel -N '' -C 'vps-to-laptop-tunnel'"
    exit 1
fi

if grep -q "vps-to-laptop-tunnel" /root/.ssh/authorized_keys 2>/dev/null; then
    sed -i '/vps-to-laptop-tunnel/d' /root/.ssh/authorized_keys
fi

echo "command=\"/root/phone-session.sh\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${TUNNEL_PUB}" >> /root/.ssh/authorized_keys

echo ""
echo "Session persistence configured."
echo "Connect on port 22 (user: root) with the same tunnel key."
echo ""
