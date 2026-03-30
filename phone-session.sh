#!/bin/bash
## Session persistence script — runs as a forced command on VPS.
## Attach or create a persistent session that survives client disconnections.

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
