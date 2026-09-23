# Build de release com bump automático de versão beta (0.0.x).
#   powershell -ExecutionPolicy Bypass -File tool/build.ps1
#   powershell -ExecutionPolicy Bypass -File tool/build.ps1 -NoBump
param(
  [switch]$NoBump
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot '_flutter.ps1')

$bumpArgs = @{}
if ($NoBump) { $bumpArgs['NoBump'] = $true }
& (Join-Path $PSScriptRoot 'bump_version.ps1') @bumpArgs | Out-Host
& $Flutter build windows --release
Write-Output "Estado: $LASTEXITCODE"
