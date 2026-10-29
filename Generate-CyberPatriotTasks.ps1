[CmdletBinding()]
param(
    [string] $TaskPath = (Join-Path $PSScriptRoot 'CyberPatriot-Tasks.txt'),
    [string] $OutputPath = (Join-Path $PSScriptRoot 'CyberPatriot-ExecuteTasks.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $TaskPath -PathType Leaf)) {
    throw "Task file not found: $TaskPath"
}

$taskFullPath = [System.IO.Path]::GetFullPath($TaskPath)
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if ([System.StringComparer]::OrdinalIgnoreCase.Equals($taskFullPath, $outputFullPath)) {
    throw 'OutputPath must differ from TaskPath.'
}
# Only these services can be disabled through the task file. Add a service here
# only after confirming it is appropriate for the competition image.
$allowedServices = @(
    'RemoteRegistry',
    'TlntSvr',
    'FTPSVC',
    'SNMP',
    'SSDPSRV',
    'upnphost',
    'RemoteAccess'
)

$tasks = [System.Collections.Generic.List[object]]::new()
$lineNumber = 0
foreach ($rawLine in Get-Content -LiteralPath $TaskPath) {
    $lineNumber++
    $line = $rawLine.Trim()

    if ($line.Length -eq 0 -or $line.StartsWith('#')) {
        continue
    }

    if ($line -match '^FIREWALL\s+ON$') {
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'Firewall'; Value = $null })
        continue
    }
    if ($line -match '^UAC\s+ON$') {
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'Uac'; Value = $null })
        continue
    }
    if ($line -match '^GUEST_ACCOUNT\s+DISABLE$') {
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'Guest'; Value = $null })
        continue
    }
    if ($line -match '^LOCAL_ACCOUNT\s+([A-Za-z0-9_.-]{1,20})\s+DISABLE$') {
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'LocalAccount'; Value = $Matches[1] })
        continue
    }
    if ($line -match '^SERVICE\s+([A-Za-z][A-Za-z0-9_-]{0,63})\s+DISABLE$') {
        $requestedService = $Matches[1]
        $service = $allowedServices | Where-Object { $_ -ieq $requestedService } | Select-Object -First 1
        if (-not $service) {
            throw "Unsupported service on line $lineNumber ('$requestedService'). Allowed services: $($allowedServices -join ', ')."
        }
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'Service'; Value = $service })
        continue
    }
    if ($line -match '^MIN_PASSWORD_LENGTH\s+(\d{1,2})$') {
        $length = [int] $Matches[1]
        if ($length -lt 8 -or $length -gt 14) {
            throw "Minimum password length on line $lineNumber must be between 8 and 14."
        }
        $tasks.Add([pscustomobject]@{ Line = $lineNumber; Kind = 'MinPasswordLength'; Value = $length })
        continue
    }

    throw ("Unrecognized or unsupported task on line " + $lineNumber + ": " + $rawLine + ". See the task format guide. No output script was written.")
}

if ($tasks.Count -eq 0) {
    throw 'The task file contains no executable tasks. Add supported task lines and try again.'
}

$generated = [System.Collections.Generic.List[string]]::new()
$generated.Add('# Generated from CyberPatriot-Tasks.txt. Review before running on your competition image.')
$generated.Add('# Run this script from an elevated Windows PowerShell prompt.')
$generated.Add('$ErrorActionPreference = ''Stop''')
$generated.Add('$script:failedTasks = 0')
$generated.Add('')
$generated.Add('function Invoke-GeneratedTask {')
$generated.Add('    param([string] $Description, [scriptblock] $Action)')
$generated.Add('    Write-Host "[TASK] $Description" -ForegroundColor Cyan')
$generated.Add('    try {')
$generated.Add('        & $Action')
$generated.Add('        Write-Host "[OK]   $Description" -ForegroundColor Green')
$generated.Add('    } catch {')
$generated.Add('        $script:failedTasks++')
$generated.Add('        Write-Host "[FAIL] $Description -- $($_.Exception.Message)" -ForegroundColor Red')
$generated.Add('    }')
$generated.Add('}')
$generated.Add('')
$generated.Add('$principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()')
$generated.Add('if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {')
$generated.Add('    throw "Open Windows PowerShell as Administrator, then run this script again."')
$generated.Add('}')
$generated.Add('')
$generated.Add('Write-Host "This will apply the tasks listed below to this Windows installation." -ForegroundColor Yellow')
$generated.Add('Write-Host "Confirm that this is the intended CyberPatriot image and that you reviewed this script." -ForegroundColor Yellow')
$generated.Add('$confirmation = Read-Host "Type APPLY to continue"')
$generated.Add('if ($confirmation -cne ''APPLY'') { Write-Host "No changes made."; exit 2 }')
$generated.Add('')

foreach ($task in $tasks) {
    $description = switch ($task.Kind) {
        'Firewall' { 'enable Windows Firewall on all profiles' }
        'Uac' { 'enable User Account Control' }
        'Guest' { 'disable the built-in Guest account' }
        'LocalAccount' { "disable local account $($task.Value)" }
        'Service' { "disable service $($task.Value)" }
        'MinPasswordLength' { "set minimum password length to $($task.Value)" }
    }

    $generated.Add("# Source task file line $($task.Line)")
    $generated.Add("Invoke-GeneratedTask -Description '$description' -Action {")

    switch ($task.Kind) {
        'Firewall' {
            $generated.Add('    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -ErrorAction Stop')
        }
        'Uac' {
            $generated.Add('    $uacPath = ''HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System''')
            $generated.Add('    New-ItemProperty -LiteralPath $uacPath -Name EnableLUA -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null')
        }
        'Guest' {
            $generated.Add('    $guest = Get-LocalUser -ErrorAction Stop | Where-Object { $_.SID.Value -match ''-501$'' } | Select-Object -First 1')
            $generated.Add('    if ($guest -and $guest.Enabled) { Disable-LocalUser -InputObject $guest -ErrorAction Stop }')
            $generated.Add('    elseif (-not $guest) { throw "Built-in Guest account was not found." }')
        }
        'LocalAccount' {
            $generated.Add(('    Disable-LocalUser -Name ''{0}'' -ErrorAction Stop' -f $task.Value))
        }
        'Service' {
            $generated.Add(('    $service = Get-Service -Name ''{0}'' -ErrorAction Stop' -f $task.Value))
            $generated.Add(('    if ($service.Status -ne ''Stopped'') {{ Stop-Service -Name ''{0}'' -Force -ErrorAction Stop }}' -f $task.Value))
            $generated.Add(('    Set-Service -Name ''{0}'' -StartupType Disabled -ErrorAction Stop' -f $task.Value))
        }
        'MinPasswordLength' {
            $generated.Add(('    & net.exe accounts ''/minpwlen:{0}''' -f $task.Value))
            $generated.Add('    if ($LASTEXITCODE -ne 0) { throw "net accounts returned exit code $LASTEXITCODE." }')
        }
    }

    $generated.Add('}')
    $generated.Add('')
}

$generated.Add('if ($script:failedTasks -gt 0) {')
$generated.Add('    Write-Host "$script:failedTasks task(s) failed. Review the messages above." -ForegroundColor Red')
$generated.Add('    exit 1')
$generated.Add('}')
$generated.Add('Write-Host "All generated tasks completed." -ForegroundColor Green')

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
Set-Content -LiteralPath $OutputPath -Value $generated -Encoding UTF8
Write-Host "Generated $OutputPath from $TaskPath"



