# Dev com hot reload (sem bump de versao, sem build de release).
#   powershell -ExecutionPolicy Bypass -File tool/dev.ps1
#
# Depois de abrir, no terminal:
#   r = hot reload   (aplica alteracoes de UI/logica sem reiniciar)
#   R = hot restart  (reinicia o estado da app)
#   q = sair
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
. (Join-Path $PSScriptRoot '_flutter.ps1')

& $Flutter run -d windows
