param(
    [Parameter(Mandatory=$true)][string]$Config,
    [string]$TaskName = "KS Light Hub"
)
$ErrorActionPreference = "Stop"
$repoPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pythonPath = Join-Path $repoPath ".venv\Scripts\pythonw.exe"
$checkPython = Join-Path $repoPath ".venv\Scripts\python.exe"
$configPath = (Resolve-Path -LiteralPath $Config).Path
if ($configPath.Contains('"')) { throw "Invalid config path" }
if (-not (Test-Path -LiteralPath $pythonPath)) { throw "Create the repo .venv and install requirements first" }
Push-Location -LiteralPath $repoPath
try {
    & $checkPython -m ks_light.service --config $configPath --check
    if ($LASTEXITCODE -ne 0) { throw "Configuration validation failed" }
} finally { Pop-Location }
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { throw "Task already exists; inspect it before replacing it" }
$account = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute $pythonPath -Argument ('-m ks_light.service --config "' + $configPath + '"') -WorkingDirectory $repoPath
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings | Out-Null
Write-Output "Registered $TaskName for future logons. It has not been started."
