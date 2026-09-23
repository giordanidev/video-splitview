# Compila o Video Splitview para Linux (x64) usando o WSL2, a partir do Windows.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_wsl_linux.ps1
#   powershell -ExecutionPolicy Bypass -File tool/build_wsl_linux.ps1 -NoBump
#   powershell -ExecutionPolicy Bypass -File tool/build_wsl_linux.ps1 -Distro Ubuntu-24.04
#
# Gera o instalador nativo de cada distro (.deb no Ubuntu, .rpm no Fedora) e
# um AppImage portátil (na primeira distro da lista). O trabalho real é feito
# por tool/linux/build.sh dentro do WSL.
param(
  [switch]$NoBump,
  [switch]$SkipSetup,
  [string[]]$Distro = @('Ubuntu-24.04', 'FedoraLinux-44')
)

$ErrorActionPreference = 'Stop'
# Saída do wsl.exe em UTF-8 (evita o texto UTF-16 ilegível).
$env:WSL_UTF8 = '1'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot '_flutter.ps1')

if (-not $NoBump) {
  & (Join-Path $PSScriptRoot 'bump_version.ps1') | Out-Host
}

$version = '0.0.0'
$versionDart = Join-Path $root 'lib\backend\generated\version.dart'
if (Test-Path $versionDart) {
  $m = [regex]::Match((Get-Content $versionDart -Raw), "appVersion\s*=\s*'([^']+)'")
  if ($m.Success) { $version = $m.Groups[1].Value }
}

function ConvertTo-WslPath([string]$winPath) {
  $full = [IO.Path]::GetFullPath($winPath)
  $drive = $full.Substring(0, 1).ToLowerInvariant()
  $rest = $full.Substring(2).Replace('\', '/')
  return "/mnt/$drive$rest"
}

$srcWsl = ConvertTo-WslPath $root
$distWsl = ConvertTo-WslPath (Join-Path $root 'dist')
$setupFlag = if ($SkipSetup) { ' --skip-setup' } else { '' }

$index = 0
foreach ($d in $Distro) {
  Write-Output ''
  Write-Output "==> Linux build (WSL): $d (v$version)"
  # AppImage só na primeira distro (evita nomes iguais); as restantes geram o
  # instalador nativo. Normaliza CRLF dos .sh antes de correr.
  $appimageFlag = if ($index -eq 0) { ' --with-appimage' } else { '' }
  $cmd = "sed -i 's/\r$//' '$srcWsl'/tool/linux/*.sh 2>/dev/null || true; " +
    "bash '$srcWsl/tool/linux/build.sh' --version '$version' --dest '$distWsl'" +
    "$setupFlag$appimageFlag 2>&1"

  # wsl.exe escreve avisos no stderr (ex.: systemd user session); não são fatais.
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  & wsl.exe -d $d -- bash -c $cmd | ForEach-Object { Write-Output $_ }
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previousEap
  if ($code -ne 0) { throw "Build Linux falhou em $d (exit $code)" }
  $index++
}

Write-Output ''
Write-Output '==> Artefactos Linux em dist/:'
Get-ChildItem -Path (Join-Path $root 'dist') -File |
  Where-Object { $_.Name -match '\.(deb|rpm|AppImage)$' } |
  Sort-Object Name | ForEach-Object { Write-Output "    $($_.Name)" }
