## Persistent Reverse SSH Tunnel -- runs as Windows service via Task Scheduler
## Laptop:22 <- VPS:REMOTE_PORT reverse tunnel
## Auto-reconnects on failure with exponential backoff (max 60s)
## Runs as SYSTEM -- all paths must be absolute, no user-profile assumptions

$ErrorActionPreference = "Continue"

# -- CONFIGURATION (edit these) --
$VPS          = "user@YOUR_VPS_IP"
$REMOTE_PORT  = 2222
$LOCAL_PORT   = 22
$SSH_EXE      = "C:\Windows\System32\OpenSSH\ssh.exe"
$SSH_KEY      = "$PSScriptRoot\keys\id_rsa"
$KNOWN_HOSTS  = "C:\Users\$env:USERNAME\.ssh\known_hosts"
$LOG_DIR      = $PSScriptRoot
$LOG          = "$LOG_DIR\tunnel.log"
$MAX_BACKOFF  = 60
$MAX_LOG_MB   = 10
# ---------------------------------

$backoff = 5

function Write-Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        "$ts  $msg" | Out-File -Append -FilePath $LOG -Encoding ASCII
    } catch {
        Write-EventLog -LogName Application -Source "SSH-Tunnel" -EventId 1000 -EntryType Error -Message $msg -ErrorAction SilentlyContinue
    }
}

function Rotate-Log {
    if (Test-Path $LOG) {
        $sizeMB = (Get-Item $LOG).Length / 1MB
        if ($sizeMB -gt $MAX_LOG_MB) {
            $archive = "$LOG_DIR\tunnel.log.1"
            Move-Item -Path $LOG -Destination $archive -Force -ErrorAction SilentlyContinue
            Write-Log "Log rotated (previous log was ${sizeMB}MB)"
        }
    }
}

# Ensure log directory exists
if (-not (Test-Path $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

# Register event source for fallback logging
try { New-EventLog -LogName Application -Source "SSH-Tunnel" -ErrorAction SilentlyContinue } catch {}

Rotate-Log
Write-Log "====== Tunnel service starting (PID: $PID) ======"
Write-Log "SSH executable: $SSH_EXE"
Write-Log "Target: $VPS | Remote port: $REMOTE_PORT | Local port: $LOCAL_PORT"

# Validate prerequisites
if (-not (Test-Path $SSH_EXE)) {
    Write-Log "FATAL: SSH executable not found at $SSH_EXE"
    exit 1
}
if (-not (Test-Path $SSH_KEY)) {
    Write-Log "FATAL: SSH private key not found at $SSH_KEY"
    exit 1
}

# Wait for network on boot -- SYSTEM starts before network is ready
$vpsIP = ($VPS -split "@")[-1]
$networkWait = 0
while ($networkWait -lt 120) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect($vpsIP, 22)
        $tcp.Close()
        Write-Log "Network is ready (waited ${networkWait}s)"
        break
    } catch {
        $networkWait += 5
        if ($networkWait -ge 120) {
            Write-Log "WARNING: Network not ready after 120s, proceeding anyway"
        }
        Start-Sleep -Seconds 5
    }
}

while ($true) {
    Rotate-Log
    Write-Log "Connecting: $VPS -R ${REMOTE_PORT}:localhost:${LOCAL_PORT}"

    $sshArgs = @("-N", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "-o", "ExitOnForwardFailure=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10", "-o", "UserKnownHostsFile=$KNOWN_HOSTS", "-i", $SSH_KEY, "-R", "${REMOTE_PORT}:localhost:${LOCAL_PORT}", $VPS)

    $startTime = Get-Date
    $stderrFile = "$LOG_DIR\ssh-stderr.tmp"

    $procParams = @{ FilePath = $SSH_EXE; ArgumentList = $sshArgs; NoNewWindow = $true; PassThru = $true; Wait = $true; RedirectStandardError = $stderrFile }
    $proc = Start-Process @procParams

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds
    $exit = $proc.ExitCode

    # Capture SSH stderr for diagnostics
    $stderr = ""
    if (Test-Path $stderrFile) {
        $stderr = (Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue)
        if ($stderr) { $stderr = $stderr.Trim() }
        Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
    }

    if ($stderr) {
        Write-Log "SSH stderr: $stderr"
    }
    Write-Log "SSH exited (code=$exit, duration=${duration}s) -- reconnecting in ${backoff}s"

    Start-Sleep -Seconds $backoff

    # Reset backoff if connection was stable (> 5 minutes)
    if ($duration -gt 300) {
        $backoff = 5
        Write-Log "Connection was stable -- backoff reset to ${backoff}s"
    } else {
        $backoff = [Math]::Min($backoff * 2, $MAX_BACKOFF)
    }
}
