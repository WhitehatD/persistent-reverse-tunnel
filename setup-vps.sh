#!/bin/bash
## Run this on your VPS to configure SSH for reverse tunnel support.
## Usage: ssh root@your-vps 'bash -s' < setup-vps.sh

set -euo pipefail

CONFIG="/etc/ssh/sshd_config.d/tunnel.conf"

echo "Configuring SSH tunnel support..."

cat > "$CONFIG" <<'EOF'
# Persistent reverse tunnel support
GatewayPorts yes
AllowTcpForwarding yes
ClientAliveInterval 30
ClientAliveCountMax 3
EOF

echo "Restarting sshd..."
systemctl restart sshd

echo ""
echo "VPS SSH configured for reverse tunnels."
echo "Config written to: $CONFIG"
echo ""
echo "Next steps:"
echo "  1. Add your laptop's public key to ~/.ssh/authorized_keys"
echo "  2. Generate a tunnel keypair: ssh-keygen -t ed25519 -f ~/.ssh/id_tunnel -N '' -C 'vps-to-laptop-tunnel'"
echo "  3. Add the tunnel public key to your laptop's administrators_authorized_keys"
echo ""
