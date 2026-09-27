# Creates launchers only; does not send commands or install a background service.
param(
    [Parameter(Mandatory=$true)][string]$Config,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$pythonPath = Join-Path $repoPath '.venv\Scripts\python.exe'
if (!(Test-Path -LiteralPath $pythonPath)) { throw 'Create the repository Python virtual environment first.' }
$configPath = (Resolve-Path -LiteralPath $Config).Path
# Validate configuration through the same client, without sending any commands.
Push-Location -LiteralPath $repoPath
try {
    $actionNames = & $pythonPath -m ks_light.controller --config $configPath
    if ($LASTEXITCODE -ne 0) { throw 'Controller configuration validation failed.' }
} finally { Pop-Location }
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$shellObject = New-Object -ComObject WScript.Shell
foreach ($actionName in $actionNames) {
    if ($actionName -notmatch '^[a-zA-Z0-9_-]{1,64}$') { throw 'Invalid action name.' }
    $linkPath = Join-Path $outputPath ($actionName + '.lnk')
    if (Test-Path -LiteralPath $linkPath) { throw "Shortcut already exists: $actionName" }
    $link = $shellObject.CreateShortcut($linkPath)
    $link.TargetPath = $pythonPath
    $link.WorkingDirectory = $repoPath
    $link.Arguments = '-m ks_light.controller --config "' + $configPath + '" ' + $actionName
    $link.Description = 'KS Light: ' + $actionName
    $link.WindowStyle = 7
    $link.Save()
}
Write-Output 'Created controller launchers. Assign them to buttons in your controller software.'
