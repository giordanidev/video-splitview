# Resolve o executavel do Flutter e expoe $Flutter para os outros scripts.
# Uso: . (Join-Path $PSScriptRoot '_flutter.ps1')
#
# Nao depende do PATH da sessao: se `flutter` nao for encontrado, procura nos
# locais habituais de instalacao.
$ErrorActionPreference = 'Stop'

function Resolve-FlutterPath {
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat'),
    (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat'),
    (Join-Path $env:USERPROFILE 'dev\flutter\bin\flutter.bat'),
    'C:\flutter\bin\flutter.bat',
    'C:\src\flutter\bin\flutter.bat'
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  return $null
}

$Flutter = Resolve-FlutterPath
if (-not $Flutter) {
  throw "Flutter nao encontrado. Instala o SDK e/ou adiciona o respetivo 'bin' ao PATH."
}

# Garante tambem o `flutter` no PATH da sessao (para o caso de chamadas diretas).
$flutterBin = Split-Path -Parent $Flutter
if (($env:Path -split ';') -notcontains $flutterBin) {
  $env:Path = "$flutterBin;$env:Path"
}
