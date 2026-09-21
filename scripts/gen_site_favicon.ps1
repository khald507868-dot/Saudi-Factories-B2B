# Generate the SF favicon from vector font outlines.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$siteRoot = Split-Path -Parent $PSScriptRoot
$brandDir = Join-Path $siteRoot 'assets\brand'
[void][System.IO.Directory]::CreateDirectory($brandDir)
$fontFamily = [System.Drawing.FontFamily]::new('Segoe UI Black')
if ($fontFamily.Name -ne 'Segoe UI Black') { throw 'Segoe UI Black is required to match the website wordmark.' }
$glyphs = [System.Drawing.Drawing2D.GraphicsPath]::new()
$secondGlyph = [System.Drawing.Drawing2D.GraphicsPath]::new()
$glyphs.AddString('S', $fontFamily, [int][System.Drawing.FontStyle]::Regular, 40, [System.Drawing.PointF]::new(0, 0), [System.Drawing.StringFormat]::GenericTypographic)
$secondGlyph.AddString('F', $fontFamily, [int][System.Drawing.FontStyle]::Regular, 40, [System.Drawing.PointF]::new(26, 0), [System.Drawing.StringFormat]::GenericTypographic)
$bounds = [System.Drawing.RectangleF]::Union($glyphs.GetBounds(), $secondGlyph.GetBounds())
$move = [System.Drawing.Drawing2D.Matrix]::new()
$move.Translate((64 - $bounds.Width) / 2 - $bounds.X, (64 - $bounds.Height) / 2 - $bounds.Y)
$glyphs.Transform($move)
$secondGlyph.Transform($move)
$move.Dispose()
$background = [System.Drawing.Drawing2D.GraphicsPath]::new()
$background.AddArc(0, 0, 24, 24, 180, 90)
$background.AddArc(40, 0, 24, 24, 270, 90)
$background.AddArc(40, 40, 24, 24, 0, 90)
$background.AddArc(0, 40, 24, 24, 90, 90)
$background.CloseFigure()
$green = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#639e70'))
$dark = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#183b24'))
$light = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml('#f3f5f3'))
function Write-IconPng([int]$size) {
    $canvas = [System.Drawing.Bitmap]::new($size * 4, $size * 4)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.ScaleTransform($size * 4 / 64.0, $size * 4 / 64.0)
    $graphics.FillPath($light, $background)
    $graphics.FillPath($green, $glyphs)
    $graphics.FillPath($dark, $secondGlyph)
    $output = [System.Drawing.Bitmap]::new($size, $size)
    $resizer = [System.Drawing.Graphics]::FromImage($output)
    $resizer.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $resizer.DrawImage($canvas, 0, 0, $size, $size)
    $stream = [System.IO.MemoryStream]::new()
    $output.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $stream.ToArray()
    $stream.Dispose(); $resizer.Dispose(); $output.Dispose(); $graphics.Dispose(); $canvas.Dispose()
    return ,$bytes
}
$culture = [System.Globalization.CultureInfo]::InvariantCulture
function Point-Text($point) { return $point.X.ToString('0.###', $culture) + ' ' + $point.Y.ToString('0.###', $culture) }
function Get-PathText($outline) {
$points = $outline.PathPoints
$types = $outline.PathTypes
$commands = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $points.Length; $i++) {
    $type = $types[$i] -band 7
    if ($type -eq 0) { $commands.Add('M' + (Point-Text $points[$i])) }
    elseif ($type -eq 1) { $commands.Add('L' + (Point-Text $points[$i])) }
    elseif ($type -eq 3) {
        $commands.Add('C' + (Point-Text $points[$i]) + ' ' + (Point-Text $points[$i + 1]) + ' ' + (Point-Text $points[$i + 2]))
        $i += 2
    }
    if (($types[$i] -band 128) -ne 0) { $commands.Add('Z') }
}
return ($commands -join ' ')
}
$svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><title>Saudi Factories - SF</title><rect width="64" height="64" rx="12" fill="#f3f5f3"/><path fill="#639e70" fill-rule="evenodd" d="' + (Get-PathText $glyphs) + '"/><path fill="#183b24" fill-rule="evenodd" d="' + (Get-PathText $secondGlyph) + '"/></svg>'
[System.IO.File]::WriteAllText((Join-Path $brandDir 'favicon.svg'), $svg, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllBytes((Join-Path $brandDir 'apple-touch-icon.png'), (Write-IconPng 180))
$sizes = @(16, 32, 48)
$images = @($sizes | ForEach-Object { ,(Write-IconPng $_) })
$ico = [System.IO.MemoryStream]::new()
$writer = [System.IO.BinaryWriter]::new($ico)
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $writer.Write([byte]$sizes[$i]); $writer.Write([byte]$sizes[$i]); $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
}
foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
$writer.Flush()
[System.IO.File]::WriteAllBytes((Join-Path $siteRoot 'favicon.ico'), $ico.ToArray())
$writer.Dispose(); $ico.Dispose(); $glyphs.Dispose(); $secondGlyph.Dispose(); $dark.Dispose(); $background.Dispose(); $fontFamily.Dispose(); $green.Dispose(); $light.Dispose()
Write-Output 'Generated SF icons.'
