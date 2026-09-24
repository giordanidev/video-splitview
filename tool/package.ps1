# Gera os artefactos de distribuicao versionados:
#   dist/video-splitview-v<ver>-windows-x64-setup.exe     (instalador Inno Setup, se disponivel)
#   dist/video-splitview-v<ver>-windows-x64-portable.zip  (portable: pasta auto-contida + READ-ME)
#
#   powershell -ExecutionPolicy Bypass -File tool/package.ps1
#   powershell -ExecutionPolicy Bypass -File tool/package.ps1 -NoBump
param(
  [switch]$NoBump
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot '_flutter.ps1')

# 1) Versao + build.
$bumpArgs = @{}
if ($NoBump) { $bumpArgs['NoBump'] = $true }
& (Join-Path $PSScriptRoot 'bump_version.ps1') @bumpArgs | Out-Host

$version = '0.0.0'
$versionDart = Join-Path $root 'lib\backend\generated\version.dart'
if (Test-Path $versionDart) {
  $m = [regex]::Match((Get-Content $versionDart -Raw), "appVersion\s*=\s*'([^']+)'")
  if ($m.Success) { $version = $m.Groups[1].Value }
}

# Sistema + arquitetura no nome dos artefactos (windows-x64, windows-arm64).
$osArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'windows-arm64' } else { 'windows-x64' }
$artifactBase = "video-splitview-v$version-$osArch"

Write-Output "A construir o release..."
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build falhou" }

$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# Manifesto de update: inclui-o nos artefactos para ser anexado a release
# (lido pela verificacao em update_service.dart).
$versionJson = Join-Path $root 'version.json'
if (Test-Path $versionJson) {
  Copy-Item -Path $versionJson -Destination (Join-Path $dist 'version.json') -Force
}

# 2) Portable (pasta auto-contida + READ-ME).
$portableDir = Join-Path $env:TEMP "$artifactBase-portable"
Remove-Item $portableDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
Copy-Item -Path (Join-Path $release '*') -Destination $portableDir -Recurse -Force
$readme = @(
  "Video Splitview $version - Portable ($osArch)",
  "Side by side, frame by frame.",
  "",
  "Runs video-splitview.exe. No installation needed.",
  "All files (including libmpv-2.dll) are in this folder.",
  "",
  "To install, use $artifactBase-setup.exe."
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $portableDir 'READ-ME.txt'), $readme)
$portableZip = Join-Path $dist "$artifactBase-portable.zip"
Remove-Item $portableZip -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $portableDir '*') -DestinationPath $portableZip
Remove-Item $portableDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "portable -> $portableZip"

# 3) Instalador (Inno Setup), se o ISCC estiver disponivel.
$iscc = $null
foreach ($candidate in @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 7\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'C:\Program Files (x86)\Inno Setup 7\ISCC.exe',
    'C:\Program Files\Inno Setup 7\ISCC.exe'
  )) {
  if ($candidate -and (Test-Path $candidate)) { $iscc = $candidate; break }
}
if (-not $iscc) {
  $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($cmd) { $iscc = $cmd.Source }
}

if ($iscc) {
  $icon = Join-Path $root 'windows\runner\resources\app_icon.ico'
  $iss = Join-Path $PSScriptRoot 'installer.iss'
  & $iscc "/DAppVersion=$version" "/DSourceDir=$release" "/DOutputDir=$dist" "/DIconFile=$icon" "/DOutputBaseName=$artifactBase-setup" $iss
  if ($LASTEXITCODE -ne 0) { throw "ISCC falhou" }
  Write-Output "setup    -> $(Join-Path $dist "$artifactBase-setup.exe")"
} else {
  Write-Output ""
  Write-Output "AVISO: Inno Setup (ISCC.exe) nao encontrado - o instalador NAO foi gerado."
  Write-Output "Instala com: winget install --id JRSoftware.InnoSetup -e"
}

Write-Output ""
Write-Output "Concluido. Versao $version. Artefactos em: $dist"
