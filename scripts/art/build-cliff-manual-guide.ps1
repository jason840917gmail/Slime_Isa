# Geometry reference only; generated art is painted separately with ImageGen.
Add-Type -AssemblyName System.Drawing
$destination = Join-Path $PSScriptRoot '../../asset/Originals/elevation/cliff-manual-prototype'
New-Item -ItemType Directory -Force $destination | Out-Null
$canvas = [System.Drawing.Bitmap]::new(1536, 1536)
$graphics = [System.Drawing.Graphics]::FromImage($canvas)
$grass = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#799642'))
$stone = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#8d857a'))
$earth = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#65462e'))
$grid = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(110, 230, 230, 230), 2)
for ($row = 0; $row -lt 6; $row++) {
 for ($col = 0; $col -lt 6; $col++) {
  $left = $col * 256; $top = $row * 256
  $x0 = 0; $x1 = 256; $y0 = 0; $y1 = 256
  $brush = $grass
  if ($col -lt 3 -and $row -lt 3) {
   if ($col -eq 0) { $x0 = 48 }
   if ($col -eq 2) { $x1 = 208 }
   if ($row -eq 0) { $y0 = 48 }
  } elseif ($row -ge 3) {
   $brush = $stone
   if ($col % 3 -eq 0) { $x0 = 48 }
   if ($col % 3 -eq 2) { $x1 = 208 }
   if ($row -eq 5 -or ($row -eq 3 -and $col -ge 3)) { $y1 = 224 }
  } elseif ($row -eq 2 -and $col -ge 3) {
   if ($col -eq 3) { $y0 = 48 }
   if ($col -eq 4) { $x0 = 48 }
   if ($col -eq 5) { $x1 = 208 }
  }
  $graphics.FillRectangle($brush, $left+$x0, $top+$y0, $x1-$x0, $y1-$y0)
  if ($row -eq 2 -and $col -lt 3) { $graphics.FillRectangle($earth, $left+$x0, $top+208, $x1-$x0, 48) }
  if ($row -eq 3) { $graphics.FillRectangle($earth, $left+$x0, $top, $x1-$x0, 32) }
  if ($row -lt 2 -and $col -in 3,4) {
   $cutX = if ($col -eq 3) { 0 } else { 208 }
   $cutY = if ($row -eq 0) { 0 } else { 208 }
   $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
   $clear = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::Transparent)
   $graphics.FillRectangle($clear, $left+$cutX, $top+$cutY, 48, 48)
   $clear.Dispose()
   $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
  }
  $graphics.DrawRectangle($grid, $left, $top, 255, 255)
 }
}
$canvas.Save((Join-Path $destination 'layout-guide.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $canvas.Dispose(); $grass.Dispose(); $stone.Dispose(); $earth.Dispose(); $grid.Dispose()
