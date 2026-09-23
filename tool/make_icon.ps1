# Gera windows/runner/resources/app_icon.ico a partir de assets/icon/video_splitview.png
# com varias resolucoes (todas em PNG, formato aceite pelo rc.exe e pelo Explorer).
#
#   powershell -ExecutionPolicy Bypass -File tool/make_icon.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $root 'assets\icon\video_splitview.png'
$outPath = Join-Path $root 'windows\runner\resources\app_icon.ico'

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$src = [System.Drawing.Image]::FromFile($srcPath)

$images = @()
foreach ($size in $sizes) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $size, $size)
  $g.Dispose()
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $images += [pscustomobject]@{ Size = $size; Bytes = $ms.ToArray() }
  $bmp.Dispose()
}
$src.Dispose()

$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$images.Count)
$offset = 6 + 16 * $images.Count
foreach ($img in $images) {
  $dim = if ($img.Size -ge 256) { 0 } else { $img.Size }
  $bw.Write([Byte]$dim)
  $bw.Write([Byte]$dim)
  $bw.Write([Byte]0)
  $bw.Write([Byte]0)
  $bw.Write([UInt16]1)
  $bw.Write([UInt16]32)
  $bw.Write([UInt32]$img.Bytes.Length)
  $bw.Write([UInt32]$offset)
  $offset += $img.Bytes.Length
}
foreach ($img in $images) {
  $bw.Write($img.Bytes)
}
$bw.Flush()
[IO.File]::WriteAllBytes($outPath, $out.ToArray())
Write-Output "app_icon.ico gerado: $((Get-Item $outPath).Length) bytes ($($images.Count) tamanhos)"
