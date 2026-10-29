# Generated from CyberPatriot-Tasks.txt. Review before running on your competition image.
# Run this script from an elevated Windows PowerShell prompt.
$ErrorActionPreference = 'Stop'
$script:failedTasks = 0

function Invoke-GeneratedTask {
    param([string] $Description, [scriptblock] $Action)
    Write-Host "[TASK] $Description" -ForegroundColor Cyan
    try {
        & $Action
        Write-Host "[OK]   $Description" -ForegroundColor Green
    } catch {
        $script:failedTasks++
        Write-Host "[FAIL] $Description -- $($_.Exception.Message)" -ForegroundColor Red
    }
}

$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Open Windows PowerShell as Administrator, then run this script again."
}

Write-Host "This will apply the tasks listed below to this Windows installation." -ForegroundColor Yellow
Write-Host "Confirm that this is the intended CyberPatriot image and that you reviewed this script." -ForegroundColor Yellow
$confirmation = Read-Host "Type APPLY to continue"
if ($confirmation -cne 'APPLY') { Write-Host "No changes made."; exit 2 }

# Source task file line 4
Invoke-GeneratedTask -Description 'enable Windows Firewall on all profiles' -Action {
    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -ErrorAction Stop
}

# Source task file line 5
Invoke-GeneratedTask -Description 'enable User Account Control' -Action {
    $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    New-ItemProperty -LiteralPath $uacPath -Name EnableLUA -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
}

# Source task file line 6
Invoke-GeneratedTask -Description 'disable the built-in Guest account' -Action {
    $guest = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -match '-501$' } | Select-Object -First 1
    if ($guest -and $guest.Enabled) { Disable-LocalUser -InputObject $guest -ErrorAction Stop }
    elseif (-not $guest) { throw "Built-in Guest account was not found." }
}

# Source task file line 7
Invoke-GeneratedTask -Description 'disable service RemoteRegistry' -Action {
    $service = Get-Service -Name 'RemoteRegistry' -ErrorAction Stop
    if ($service.Status -ne 'Stopped') { Stop-Service -Name 'RemoteRegistry' -Force -ErrorAction Stop }
    Set-Service -Name 'RemoteRegistry' -StartupType Disabled -ErrorAction Stop
}

if ($script:failedTasks -gt 0) {
    Write-Host "$script:failedTasks task(s) failed. Review the messages above." -ForegroundColor Red
    exit 1
}
Write-Host "All generated tasks completed." -ForegroundColor Green
