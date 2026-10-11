param([Parameter(Mandatory=$true)][string]$SourcePath)
# Packing only: fixed grid resampling, no seam repair or silhouette reshaping.
Add-Type -AssemblyName System.Drawing
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$originals = Join-Path $root 'asset/Originals/elevation/cliff-manual-prototype'
$runtime = Join-Path $root 'godot/asset/MAPS/cliffs/manual-prototype'
New-Item -ItemType Directory -Force $originals,$runtime | Out-Null
Copy-Item -LiteralPath $SourcePath -Destination (Join-Path $originals 'painted-master.png')
$source = [System.Drawing.Bitmap]::new($SourcePath)
$sheet = [System.Drawing.Bitmap]::new(768,768)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
for ($row=0;$row -lt 6;$row++) {
 for ($col=0;$col -lt 6;$col++) {
  $src = [System.Drawing.RectangleF]::new($col*$source.Width/6, $row*$source.Height/6, $source.Width/6, $source.Height/6)
  $dst = [System.Drawing.RectangleF]::new($col*128,$row*128,128,128)
  $graphics.DrawImage($source,$dst,$src,[System.Drawing.GraphicsUnit]::Pixel)
 }
}
$sheet.Save((Join-Path $runtime '128x128-tile_6x6-cliff-manual.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $sheet.Dispose(); $source.Dispose()
