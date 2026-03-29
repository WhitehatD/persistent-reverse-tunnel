#Requires -RunAsAdministrator
## Run this on your Windows laptop to install and configure OpenSSH Server.
## After running, add your VPS tunnel public key to administrators_authorized_keys.

set -euo pipefail

Write-Host "Installing OpenSSH Server..." -ForegroundColor Cyan
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Write-Host "Starting and enabling sshd..." -ForegroundColor Cyan
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

Write-Host ""
Write-Host "OpenSSH Server installed and running." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add your VPS tunnel public key to:"
Write-Host "     C:\ProgramData\ssh\administrators_authorized_keys"
Write-Host ""
Write-Host "  2. Set correct permissions:"
Write-Host "     icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'SYSTEM:(R)' /grant 'Administrators:(R)'"
Write-Host ""
Write-Host "  3. Restart sshd:"
Write-Host "     Restart-Service sshd"
Write-Host ""
