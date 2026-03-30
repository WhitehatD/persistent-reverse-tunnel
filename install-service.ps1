#Requires -RunAsAdministrator
## Installs the SSH tunnel as a persistent Windows scheduled task running as SYSTEM.
## SYSTEM has network access at boot -- no S4U token limitations.
## Also copies the SSH key with restricted permissions for SYSTEM.
## Run this script once as Administrator.

$ErrorActionPreference = "Stop"

# -- CONFIGURATION --
$taskName     = "SSH-Reverse-Tunnel"
$scriptPath   = "$PSScriptRoot\tunnel.ps1"
$sourceKey    = "$env:USERPROFILE\.ssh\id_rsa"
$tunnelKeyDir = "$PSScriptRoot\keys"
$tunnelKey    = "$tunnelKeyDir\id_rsa"
# -------------------

# --- Key Setup ---
Write-Host "Setting up SSH key for SYSTEM..." -ForegroundColor Cyan

if (-not (Test-Path $tunnelKeyDir)) {
    New-Item -ItemType Directory -Path $tunnelKeyDir -Force | Out-Null
}
Copy-Item -Path $sourceKey -Destination $tunnelKey -Force

# Restrict permissions: SYSTEM + Administrators read-only (OpenSSH requirement)
$acl = Get-Acl $tunnelKey
$acl.SetAccessRuleProtection($true, $false)
$acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) } | Out-Null
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM", "Read", "Allow")))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators", "Read", "Allow")))
Set-Acl -Path $tunnelKey -AclObject $acl

Write-Host "Key permissions set (SYSTEM + Administrators: Read only)" -ForegroundColor Green

# --- Task Setup ---
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Trigger: at startup with 15s delay for networking
$trigger = New-ScheduledTaskTrigger -AtStartup
$trigger.Delay = "PT15S"

# Action: run via cmd.exe wrapper (avoids PowerShell CRLF/encoding issues under SYSTEM)
$cmdArg = '/c powershell.exe -NoProfile -ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File "' + $scriptPath + '"'
$action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $cmdArg -WorkingDirectory $PSScriptRoot

# Settings: never stop, restart on failure, run on battery
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

# Principal: SYSTEM -- has network access, runs at boot, no password needed
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Settings $settings -Principal $principal -Description "Persistent reverse SSH tunnel -- self-healing, runs as SYSTEM at boot" -Force

Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "Installed and started: $taskName" -ForegroundColor Green
Write-Host "Runs as: SYSTEM (network-capable, boot-time start)" -ForegroundColor Cyan
Write-Host "Logs: $PSScriptRoot\tunnel.log"
Write-Host ""

Start-Sleep -Seconds 5
$task = Get-ScheduledTask -TaskName $taskName
Write-Host "Task State: $($task.State)" -ForegroundColor Yellow

if (Test-Path "$PSScriptRoot\tunnel.log") {
    Write-Host ""
    Write-Host "Recent log:" -ForegroundColor Green
    Get-Content "$PSScriptRoot\tunnel.log" -Tail 5
}
