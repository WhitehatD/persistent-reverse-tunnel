#Requires -RunAsAdministrator
## Installs the SSH tunnel as a persistent Windows scheduled task.
## Run this script once as Administrator.

# ── CONFIGURATION ──────────────────────────────────────────────
$taskName   = "SSH-Reverse-Tunnel"
$scriptPath = "$PSScriptRoot\tunnel.ps1"
$username   = $env:USERNAME
# ───────────────────────────────────────────────────────────────

# Remove existing task if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Triggers: at logon + at startup (covers reboots and re-logins)
$triggerLogon   = New-ScheduledTaskTrigger -AtLogOn -User $username
$triggerStartup = New-ScheduledTaskTrigger -AtStartup

# Action: run the tunnel script hidden (no console window)
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Settings: never stop, restart on failure, run on battery
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Days 0)

# Principal: run as current user with highest privileges
$principal = New-ScheduledTaskPrincipal `
    -UserId $username `
    -LogonType S4U `
    -RunLevel Highest

# Register and start
Register-ScheduledTask `
    -TaskName $taskName `
    -Trigger $triggerLogon, $triggerStartup `
    -Action $action `
    -Settings $settings `
    -Principal $principal `
    -Description "Persistent reverse SSH tunnel — auto-reconnecting, self-healing"

Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "Installed and started: $taskName" -ForegroundColor Green
Write-Host "Logs: $PSScriptRoot\tunnel.log"
Write-Host ""
Get-ScheduledTask -TaskName $taskName | Select-Object TaskName, State | Format-Table
