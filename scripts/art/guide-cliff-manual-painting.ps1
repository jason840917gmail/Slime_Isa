# Annotation diagram only. Does not modify the runtime sheet.
Add-Type -AssemblyName System.Drawing
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$source = [System.Drawing.Bitmap]::new((Join-Path $root 'godot/asset/MAPS/cliffs/manual-prototype/128x128-tile_6x6-cliff-manual.png'))
$guide = [System.Drawing.Bitmap]::new(1688,1990)
$graphics = [System.Drawing.Graphics]::FromImage($guide)
$graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#20251b'))
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$font = [System.Drawing.Font]::new('Arial',16)
$title = [System.Drawing.Font]::new('Arial',24,[System.Drawing.FontStyle]::Bold)
$white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
$yellow = [System.Drawing.Pen]::new([System.Drawing.Color]::Gold,3)
$red = [System.Drawing.Pen]::new([System.Drawing.Color]::Tomato,5)
$cyan = [System.Drawing.Pen]::new([System.Drawing.Color]::Cyan,2)
$graphics.DrawString('FIXED 128px TILES - PAINTING REPAIR MAP',$title,$white,20,12)
$graphics.DrawString('A-F = columns, 1-6 = rows. Yellow = match joins. Red = repaint priority. Cyan = rim guides.',$font,$white,20,55)
for ($row=0;$row -lt 6;$row++) {
 for ($col=0;$col -lt 6;$col++) {
  $x=20+$col*276; $y=115+$row*286
  $code=([char](65+$col)).ToString()+($row+1)
  $graphics.DrawString($code,$font,$white,$x,$y-25)
  $dst=[System.Drawing.Rectangle]::new($x,$y,256,256)
  $src=[System.Drawing.Rectangle]::new($col*128,$row*128,128,128)
  $graphics.DrawImage($source,$dst,$src,[System.Drawing.GraphicsUnit]::Pixel)
  $graphics.DrawRectangle($yellow,$dst)
  if (($row -eq 1 -and $col -eq 1) -or ($row -eq 3 -and $col -lt 3) -or ($row -eq 4 -and $col -eq 1) -or ($col -in 3,4 -and $row -lt 2) -or ($row -eq 2 -and $col -ge 3)) {
   $graphics.DrawRectangle($red,$x-3,$y-3,262,262)
  }
  if ($col -eq 0 -and $row -lt 3) { $graphics.DrawLine($cyan,$x+48,$y,$x+48,$y+256) }
  if ($col -eq 2 -and $row -lt 3) { $graphics.DrawLine($cyan,$x+208,$y,$x+208,$y+256) }
  if ($row -eq 0 -and $col -lt 3) { $graphics.DrawLine($cyan,$x,$y+48,$x+256,$y+48) }
  if ($row -eq 2 -and $col -lt 3) { $graphics.DrawLine($cyan,$x,$y+208,$x+256,$y+208) }
 }
}
$graphics.DrawString('1  B2: quieter grass; match left/right and top/bottom before adding variants.',$font,$white,20,1840)
$graphics.DrawString('2  A4-C4: remove second grass fringe. Keep soil, roots and stone only.',$font,$white,20,1875)
$graphics.DrawString('3  B5 then A5/C5: make rock repeat BOTH horizontally and vertically.',$font,$white,20,1910)
$graphics.DrawString('4  D1/E1/D2/E2 and D3-F3: repaint exact corner and one-sided rim shapes.',$font,$white,20,1945)
$guide.Save((Join-Path $root 'docs/godot/cliff-manual-painting-guide.png'),[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $guide.Dispose(); $source.Dispose(); $font.Dispose(); $title.Dispose(); $white.Dispose(); $yellow.Dispose(); $red.Dispose(); $cyan.Dispose()
