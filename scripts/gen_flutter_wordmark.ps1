param(
    [string]$FontFamily = 'Segoe UI Black'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Convert only the three brand words into vector outlines. No font binary is
# copied or bundled. The source styling is the web logo: 19px main lettering,
# 0.62em B2B lettering raised by 0.58 of its own em above the main baseline.
# Run on Windows with the named Segoe UI face installed.
$wordmarkRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$wordmarkOutput = Join-Path $wordmarkRoot 'app_flutter/lib/widgets/wordmark_paths.dart'
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$mainSize = [single]19
$suffixSize = [single]($mainSize * 0.62)
$suffixRaise = [single]($suffixSize * 0.58)
$fontStyle = [System.Drawing.FontStyle]::Regular
if ($FontFamily -eq 'Segoe UI') {
    $fontStyle = [System.Drawing.FontStyle]::Bold
}

$family = [System.Drawing.FontFamily]::new($FontFamily)
if ($family.Name -ne $FontFamily) {
    throw "The requested font family is unavailable: $FontFamily"
}
$mainFont = [System.Drawing.Font]::new($family, $mainSize, $fontStyle, [System.Drawing.GraphicsUnit]::Pixel)
$suffixFont = [System.Drawing.Font]::new($family, $suffixSize, $fontStyle, [System.Drawing.GraphicsUnit]::Pixel)
$bitmap = [System.Drawing.Bitmap]::new(1, 1)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$format = [System.Drawing.StringFormat]::GenericTypographic.Clone()
$format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces -bor [System.Drawing.StringFormatFlags]::NoClip
$paths = [System.Collections.Generic.List[System.Drawing.Drawing2D.GraphicsPath]]::new()

function Format-Coordinate([double]$Value) {
    if ([Math]::Abs($Value) -lt 0.000005) { $Value = 0 }
    $result = $Value.ToString('0.#####', $invariant)
    if (-not $result.Contains('.')) { $result += '.0' }
    return $result
}

function Get-Advance([string]$Text, [System.Drawing.Font]$Font) {
    return [double]$graphics.MeasureString($Text, $Font, [int]::MaxValue, $format).Width
}

function Add-WordPath([string]$Text, [single]$Size, [double]$X, [double]$Y) {
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddString($Text, $family, [int]$fontStyle, $Size, [System.Drawing.PointF]::new([single]$X, [single]$Y), $format)
    $paths.Add($path)
}

function Write-DartPath([System.Text.StringBuilder]$Builder, [string]$Name, [System.Drawing.Drawing2D.GraphicsPath]$Path) {
    [void]$Builder.AppendLine("  static final Path $Name = Path()")
    $points = $Path.PathPoints
    $types = $Path.PathTypes
    $index = 0
    while ($index -lt $points.Length) {
        $pointType = $types[$index] -band 7
        if ($pointType -eq 0 -or $pointType -eq 1) {
            $operation = if ($pointType -eq 0) { 'moveTo' } else { 'lineTo' }
            $x = Format-Coordinate $points[$index].X
            $y = Format-Coordinate $points[$index].Y
            [void]$Builder.AppendLine("    ..$operation($x, $y)")
            if (($types[$index] -band 128) -ne 0) { [void]$Builder.AppendLine('    ..close()') }
            $index++
        } elseif ($pointType -eq 3) {
            if ($index + 2 -ge $points.Length -or ($types[$index + 1] -band 7) -ne 3 -or ($types[$index + 2] -band 7) -ne 3) {
                throw 'Unexpected incomplete cubic segment in glyph outlines.'
            }
            $coordinates = foreach ($offset in 0..2) {
                Format-Coordinate $points[$index + $offset].X
                Format-Coordinate $points[$index + $offset].Y
            }
            [void]$Builder.AppendLine(('    ..cubicTo({0})' -f ($coordinates -join ', ')))
            if (($types[$index + 2] -band 128) -ne 0) { [void]$Builder.AppendLine('    ..close()') }
            $index += 3
        } else {
            throw "Unsupported glyph point type: $pointType"
        }
    }
    # End the final cascade expression without an extra empty statement.
    $Builder.Length -= [Environment]::NewLine.Length
    [void]$Builder.AppendLine(';')
    [void]$Builder.AppendLine()
}

try {
    $ascentRatio = [double]$family.GetCellAscent($fontStyle) / $family.GetEmHeight($fontStyle)
    $mainBaseline = $mainSize * $ascentRatio
    $suffixY = $mainBaseline - $suffixRaise - $suffixSize * $ascentRatio
    $spaceAdvance = Get-Advance ' ' $mainFont
    $saudiAdvance = Get-Advance 'Saudi' $mainFont
    $factoriesAdvance = Get-Advance 'Factories' $mainFont
    $suffixAdvance = Get-Advance 'B2B' $suffixFont
    if ($FontFamily -eq 'Segoe UI Black') {
        # Chrome resolves the web's Segoe UI weight 800 to Segoe UI Black.
        # Use its measured CSS advances at 19px (B2B at 11.78px): GDI uses
        # slightly different fractional advances, accumulating about 0.04px.
        $saudiAdvance = 51.484375
        $factoriesAdvance = 84.28125
        $spaceAdvance = 5.28125
        $suffixAdvance = 23.34375
    }
    $factoriesX = $saudiAdvance + $spaceAdvance
    $suffixX = $factoriesX + $factoriesAdvance + $spaceAdvance
    $fullAdvance = $suffixX + $suffixAdvance

    Add-WordPath 'Saudi' $mainSize 0 0
    Add-WordPath 'Factories' $mainSize $factoriesX 0
    Add-WordPath 'B2B' $suffixSize $suffixX $suffixY

    $bounds = $paths[0].GetBounds()
    foreach ($path in $paths | Select-Object -Skip 1) {
        $bounds = [System.Drawing.RectangleF]::Union($bounds, $path.GetBounds())
    }
    $logicalWidth = [Math]::Max($fullAdvance, $bounds.Right) - $bounds.Left
    $logicalHeight = $bounds.Height
    $transform = [System.Drawing.Drawing2D.Matrix]::new()
    try {
        $transform.Translate(-$bounds.Left, -$bounds.Top)
        foreach ($path in $paths) { $path.Transform($transform) }
    } finally {
        $transform.Dispose()
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('// Generated by scripts/gen_flutter_wordmark.ps1. Do not edit by hand.')
    [void]$builder.AppendLine('// Vector logo outlines of the existing web brand text; not a font asset.')
    [void]$builder.AppendLine("// Source face: $FontFamily ($fontStyle). Main size 19; B2B 0.62em raised 0.58em.")
    [void]$builder.AppendLine("import 'dart:ui';")
    [void]$builder.AppendLine()
    [void]$builder.AppendLine('abstract final class SFWordmarkPaths {')
    [void]$builder.AppendLine(('  static const double width = {0};' -f (Format-Coordinate $logicalWidth)))
    [void]$builder.AppendLine(('  static const double height = {0};' -f (Format-Coordinate $logicalHeight)))
    [void]$builder.AppendLine()
    Write-DartPath $builder 'saudi' $paths[0]
    Write-DartPath $builder 'factories' $paths[1]
    Write-DartPath $builder 'b2b' $paths[2]
    $builder.Length -= [Environment]::NewLine.Length
    [void]$builder.AppendLine('}')
    [System.IO.File]::WriteAllText($wordmarkOutput, $builder.ToString().Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Output ("Generated {0}: width={1}, ink height={2}, B2B raise={3}" -f $wordmarkOutput, (Format-Coordinate $logicalWidth), (Format-Coordinate $logicalHeight), (Format-Coordinate $suffixRaise))
} finally {
    foreach ($path in $paths) { $path.Dispose() }
    $format.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $suffixFont.Dispose()
    $mainFont.Dispose()
    $family.Dispose()
}
