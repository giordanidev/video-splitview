# Faz bump a versao beta (0.0.x) e gera lib/generated/version.dart.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tool/bump_version.ps1
#   powershell -ExecutionPolicy Bypass -File tool/bump_version.ps1 -NoBump
#
# Regras:
#   - pubspec.yaml "version: 0.0.PATCH+BUILD" -> PATCH+1 e BUILD+1
#   - lib/generated/version.dart recebe appVersion='0.0.PATCH' e appCommit=<sha curto>
#   - version.json (manifesto de update) recebe version + releaseUrl
param(
  [switch]$NoBump
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root 'pubspec.yaml'
$versionDartPath = Join-Path $root 'lib\backend\generated\version.dart'
$versionJsonPath = Join-Path $root 'version.json'

$content = Get-Content -LiteralPath $pubspecPath -Raw
$match = [regex]::Match($content, 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)')
if (-not $match.Success) {
  throw "Nao encontrei 'version: X.Y.Z+B' em pubspec.yaml"
}

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value
$newVersion = "version: $major.$minor.$patch+$build"

if (-not $NoBump) {
  $patch += 1
  $build += 1
  $newVersion = "version: $major.$minor.$patch+$build"
  $content = $content.Substring(0, $match.Index) + $newVersion + $content.Substring($match.Index + $match.Length)
  [IO.File]::WriteAllText($pubspecPath, $content)
}

# Commit curto (se nao houver git, usa 'dev').
$commit = 'dev'
try {
  $commit = (git -C $root rev-parse --short HEAD 2>$null)
  if ($null -ne $commit) { $commit = $commit.Trim() }
  if ([string]::IsNullOrWhiteSpace($commit)) { $commit = 'dev' }
} catch { $commit = 'dev' }

$appVersion = "$major.$minor.$patch"
$lines = @(
  '// GERADO AUTOMATICAMENTE por tool/bump_version.ps1.',
  '// Nao editar a mao.',
  "const String appVersion = '$appVersion';",
  "const String appCommit = '$commit';",
  ''
)
[IO.File]::WriteAllText($versionDartPath, ($lines -join "`n"))

# Manifesto de atualizacao: publicado como asset da release e servido pela CDN
# a partir do ramo main. Lido pela verificacao de updates (update_service.dart).
$versionJson = @(
  '{',
  "  `"version`": `"$appVersion`",",
  '  "releaseUrl": "https://github.com/giordanidev/video-splitview/releases"',
  '}',
  ''
)
[IO.File]::WriteAllText($versionJsonPath, ($versionJson -join "`n"))

Write-Output "Versao: v$appVersion ($commit) | pubspec: $newVersion"
