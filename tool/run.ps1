# Dev com bump automático de versão beta (0.0.x).
#   powershell -ExecutionPolicy Bypass -File tool/run.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot '_flutter.ps1')

& (Join-Path $PSScriptRoot 'bump_version.ps1')
& $Flutter run -d windows
