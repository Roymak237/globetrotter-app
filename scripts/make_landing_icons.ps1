# Produce the web-sized copies of the app icon that the landing page uses.
#
# Re-run this after changing frontend/assets/icons/icon.png so the site and the
# installed app never drift apart:
#
#   powershell -ExecutionPolicy Bypass -File scripts/make_landing_icons.ps1
#
# Why JPEG rather than PNG: the source artwork is a full-bleed gradient with no
# transparency, which is the worst case for PNG's filtering. Measured at 384px
# the same image is 305 KB as PNG-24 against 44 KB as JPEG q94 — a 7x saving
# for no visible difference. The icon has opaque square corners, so the page
# rounds them with CSS; nothing depends on an alpha channel.
#
# Only two sizes are emitted because only two are used. The hero renders at a
# maximum of 136 CSS px, so 384 covers it even on a 2x display, and 192 covers
# the 40 px nav and footer marks at any density.

Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root "frontend\assets\icons\icon.png"
$outDir = Join-Path $root "frontend\landing"

if (-not (Test-Path $src)) { throw "Source icon not found at $src" }

$encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
  Where-Object { $_.MimeType -eq "image/jpeg" }

$params = New-Object System.Drawing.Imaging.EncoderParameters(1)
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
  [System.Drawing.Imaging.Encoder]::Quality, [long]94)

foreach ($px in 192, 384) {
  $img = [System.Drawing.Image]::FromFile($src)
  $bmp = New-Object System.Drawing.Bitmap($px, $px)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.DrawImage($img, 0, 0, $px, $px)
  $g.Dispose()

  $dest = Join-Path $outDir "app-icon-$px.jpg"
  $bmp.Save($dest, $encoder, $params)
  $bmp.Dispose()
  $img.Dispose()

  $kb = [math]::Round((Get-Item $dest).Length / 1KB, 1)
  Write-Output ("app-icon-{0}.jpg  {0}x{0}  {1} KB" -f $px, $kb)
}
