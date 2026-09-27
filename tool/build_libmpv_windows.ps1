<#
.SYNOPSIS
  Compila o libmpv do Windows (codec set completo do FFmpeg) via MSYS2.

.DESCRIPTION
  O `media_kit_libs_windows_video` embute um libmpv com uma whitelist de codecs
  (sem Bink, ProRes, DNxHD, MXF, VC-1, WMV, image2, VobSub, ...). Este script
  compila o nosso, mantendo LGPL, e copia-o para
  `third_party/libmpv/windows-x64/`, de onde `windows/CMakeLists.txt` o instala
  por cima do do plugin.

  Requer MSYS2 instalado (https://www.msys2.org). O script bash faz o resto
  (instala os pacotes em falta, compila FFmpeg + libmpv).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\build_libmpv_windows.ps1
#>
[CmdletBinding()]
param(
  # Directorio de trabalho (fontes + logs). Usa F:\libmpv-build por omissao.
  [string]$WorkDir = 'F:\libmpv-build'
)

$ErrorActionPreference = 'Stop'

$msys = 'C:\msys64\usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $msys)) {
  throw "MSYS2 nao encontrado em $msys. Instala em https://www.msys2.org e volta a correr."
}

$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'build_libmpv_windows.sh'
if (-not (Test-Path -LiteralPath $script)) { throw "Falta $script" }

# Caminho POSIX do workdir (/f/libmpv-build -> F:\libmpv-build).
$posix = ($WorkDir -replace '^([A-Za-z]):', '/$1'.ToLower()) -replace '\\', '/'
$posix = $posix.Substring(0, 2).ToLower() + $posix.Substring(2)

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$env:MSYSTEM = 'MINGW64'
$env:LIBMPV_BUILD_ROOT = $posix

Write-Host "A compilar o libmpv (workdir: $posix). Pode demorar 30-60 min na primeira vez." -ForegroundColor Cyan
& $msys -l "bash '$($script -replace '\\', '/')'"
if ($LASTEXITCODE -ne 0) { throw "build falhou (exit $LASTEXITCODE). Log em $WorkDir\logs\build_libmpv.log" }

$dll = Join-Path $repo 'third_party\libmpv\windows-x64\libmpv-2.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "DLL nao encontrada em $dll" }
$mb = [math]::Round((Get-Item -LiteralPath $dll).Length / 1MB, 1)
Write-Host "OK: $dll ($mb MB). Rebuild do Windows para usar." -ForegroundColor Green
