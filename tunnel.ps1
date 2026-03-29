## Persistent Reverse SSH Tunnel — runs as Windows service via Task Scheduler
## Laptop:22 ← VPS:REMOTE_PORT reverse tunnel
## Auto-reconnects on failure with exponential backoff (max 60s)

# ── CONFIGURATION ──────────────────────────────────────────────
$VPS          = "user@YOUR_VPS_IP"          # VPS SSH connection string
$REMOTE_PORT  = 2222                        # Port the VPS exposes for tunnel
$LOCAL_PORT   = 22                          # Local SSH server port
$SSH_KEY      = "$env:USERPROFILE\.ssh\id_rsa"  # Private key for VPS auth
$LOG          = "$PSScriptRoot\tunnel.log"  # Log file path
$MAX_BACKOFF  = 60                          # Max seconds between retries
# ───────────────────────────────────────────────────────────────

$backoff = 5

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  $msg" | Out-File -Append -FilePath $LOG -Encoding ASCII
}

Write-Log "Tunnel service starting"

while ($true) {
    Write-Log "Connecting: VPS:$REMOTE_PORT -> localhost:$LOCAL_PORT"

    $proc = Start-Process -FilePath "C:\Windows\System32\OpenSSH\ssh.exe" -ArgumentList @(
        "-N",                                # No remote command — tunnel only
        "-o", "BatchMode=yes",               # No interactive prompts
        "-o", "ServerAliveInterval=15",      # Keepalive every 15s
        "-o", "ServerAliveCountMax=3",       # Drop after 3 misses (45s)
        "-o", "ExitOnForwardFailure=yes",    # Fail if port bind fails
        "-o", "StrictHostKeyChecking=no",    # Accept new host keys
        "-o", "ConnectTimeout=10",           # Connection timeout
        "-i", $SSH_KEY,
        "-R", "${REMOTE_PORT}:localhost:${LOCAL_PORT}",
        $VPS
    ) -NoNewWindow -PassThru -Wait

    $exit = $proc.ExitCode
    Write-Log "SSH exited with code $exit — reconnecting in ${backoff}s"

    Start-Sleep -Seconds $backoff
    $backoff = [Math]::Min($backoff * 2, $MAX_BACKOFF)

    # Reset backoff if connection lasted > 5 minutes (was stable)
    if ($proc.ExitTime -and $proc.StartTime) {
        $duration = ($proc.ExitTime - $proc.StartTime).TotalSeconds
        if ($duration -gt 300) {
            $backoff = 5
            Write-Log "Connection was stable (${duration}s) — backoff reset"
        }
    }
}
