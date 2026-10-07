# Generates LanCloud app icons: Android adaptive icons (foreground/monochrome
# layers plus night background color), the iOS AppIcon set and the Windows .ico.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_app_icons.ps1
#        powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_app_icons.ps1 -WindowsOnly
#
# Icon spec:
#   - Foreground layer icon_foreground.png 432x432 (transparent)
#   - Monochrome layer icon_monochrome.png 432x432 (transparent, Android 13 themed icons)
#   - Default light background #0AC4E0 (Android adaptive icon and iOS icons)
#   - Dark background #3E3E75 (Android values-night only, see values-night/colors.xml)
param(
    [string]$ForegroundPath = 'C:\Users\Potato\Desktop\LanCloudDev\icon_foreground.png',
    [string]$MonochromePath = 'C:\Users\Potato\Desktop\LanCloudDev\icon_monochrome.png',
    [string]$LightBackground = '#0AC4E0',
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..'),
    # Regenerate the Windows .ico only (leave Android / iOS assets untouched)
    [switch]$WindowsOnly,
    # Source artwork for the Windows .ico. Defaults to the 432x432 foreground
    # layer already checked in under android/, so the exe icon matches the
    # shipped app icon even when the external source above has moved on.
    [string]$WindowsSourcePath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

function Convert-ToColor([string]$Hex) {
    $h = $Hex.TrimStart('#')
    if ($h.Length -ne 6) { throw "Invalid color: $Hex" }
    return [System.Drawing.Color]::FromArgb(
        255,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function Get-ContentBox([System.Drawing.Bitmap]$Bmp) {
    $minX = $Bmp.Width; $minY = $Bmp.Height; $maxX = -1; $maxY = -1
    for ($y = 0; $y -lt $Bmp.Height; $y++) {
        for ($x = 0; $x -lt $Bmp.Width; $x++) {
            if ($Bmp.GetPixel($x, $y).A -gt 8) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    return @{ X = $minX; Y = $minY; Width = ($maxX - $minX + 1); Height = ($maxY - $minY + 1) }
}

function New-Graphics([System.Drawing.Bitmap]$Bmp) {
    $g = [System.Drawing.Graphics]::FromImage($Bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $g
}

function Save-Png([System.Drawing.Bitmap]$Bmp, [string]$Path) {
    $dir = Split-Path -Parent $Path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-TransparentScaled([System.Drawing.Image]$Src, [int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-Graphics $bmp
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($Src, 0, 0, $Size, $Size)
    $g.Dispose()
    return $bmp
}

function New-Composite([System.Drawing.Image]$Src, [int]$Size, [System.Drawing.Color]$Bg, [double]$ContentFraction, [hashtable]$Box) {
    # 24bpp RGB so the saved PNG has no alpha channel (required by the App Store for iOS icons).
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-Graphics $bmp
    $g.Clear($Bg)
    $scale = ($Size * $ContentFraction) / $Box.Width
    $w = [int][Math]::Round($Src.Width * $scale)
    $h = [int][Math]::Round($Src.Height * $scale)
    $x = [int][Math]::Round(($Size - $w) / 2.0)
    $y = [int][Math]::Round(($Size - $h) / 2.0)
    $g.DrawImage($Src, $x, $y, $w, $h)
    $g.Dispose()
    return $bmp
}

function New-RoundedComposite([System.Drawing.Image]$Src, [int]$Size, [System.Drawing.Color]$Bg, [double]$ContentFraction, [hashtable]$Box, [double]$RadiusFraction) {
    # Windows 11 icons are usually rounded squares (WeChat / QQ style): draw the
    # tile as usual, then clip it to a rounded rectangle so the corners stay
    # transparent instead of showing a hard square edge.
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = New-Graphics $bmp
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $radius = [Math]::Max(1.0, $Size * $RadiusFraction)
    $d = $radius * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($Size - $d, 0, $d, $d, 270, 90)
    $path.AddArc($Size - $d, $Size - $d, $d, $d, 0, 90)
    $path.AddArc(0, $Size - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $g.SetClip($path)

    $brush = New-Object System.Drawing.SolidBrush($Bg)
    $g.FillRectangle($brush, 0, 0, $Size, $Size)
    $scale = ($Size * $ContentFraction) / $Box.Width
    $w = [int][Math]::Round($Src.Width * $scale)
    $h = [int][Math]::Round($Src.Height * $scale)
    $x = [int][Math]::Round(($Size - $w) / 2.0)
    $y = [int][Math]::Round(($Size - $h) / 2.0)
    $g.DrawImage($Src, $x, $y, $w, $h)

    $brush.Dispose()
    $path.Dispose()
    $g.Dispose()
    return $bmp
}

function Save-Ico([string]$Path, [System.Drawing.Image]$Src, [System.Drawing.Color]$Bg, [double]$ContentFraction, [hashtable]$Box, [int[]]$Sizes, [double]$RadiusFraction = 0) {
    # ICO directory followed by one PNG frame per size (PNG frames need Vista+).
    $frames = @()
    foreach ($size in $Sizes) {
        if ($RadiusFraction -gt 0) {
            $b = New-RoundedComposite $Src $size $Bg $ContentFraction $Box $RadiusFraction
        } else {
            $b = New-Composite $Src $size $Bg $ContentFraction $Box
        }
        $ms = New-Object System.IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $frames += , @($size, $ms.ToArray())
        $ms.Dispose()
        $b.Dispose()
    }
    $dir = Split-Path -Parent $Path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([UInt16]0)          # reserved
        $bw.Write([UInt16]1)          # type: 1 = icon
        $bw.Write([UInt16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($f in $frames) {
            # width/height of 0 means 256px
            $dim = if ($f[0] -ge 256) { 0 } else { $f[0] }
            $bw.Write([Byte]$dim)
            $bw.Write([Byte]$dim)
            $bw.Write([Byte]0)        # color count
            $bw.Write([Byte]0)        # reserved
            $bw.Write([UInt16]1)      # color planes
            $bw.Write([UInt16]32)     # bits per pixel
            $bw.Write([UInt32]$f[1].Length)
            $bw.Write([UInt32]$offset)
            $offset += $f[1].Length
        }
        foreach ($f in $frames) { $bw.Write($f[1]) }
    } finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

$fg = [System.Drawing.Bitmap]::FromFile($ForegroundPath)
$mono = [System.Drawing.Bitmap]::FromFile($MonochromePath)
if ($fg.Width -ne 432 -or $fg.Height -ne 432) { throw "Foreground must be 432x432, got $($fg.Width)x$($fg.Height)" }
if ($mono.Width -ne 432 -or $mono.Height -ne 432) { throw "Monochrome must be 432x432, got $($mono.Width)x$($mono.Height)" }

$box = Get-ContentBox $fg
Write-Host ("Foreground content box: w={0} h={1} ({2:P0} of the 432 canvas)" -f $box.Width, $box.Height, ($box.Width / 432.0))

$lightBg = Convert-ToColor $LightBackground
$resDir = Join-Path $ProjectRoot 'android\app\src\main\res'

$densities = @(
    @{ Name = 'mdpi';    Scale = 1.0 },
    @{ Name = 'hdpi';    Scale = 1.5 },
    @{ Name = 'xhdpi';   Scale = 2.0 },
    @{ Name = 'xxhdpi';  Scale = 3.0 },
    @{ Name = 'xxxhdpi'; Scale = 4.0 }
)

if (!$WindowsOnly) {
# 1) Android: adaptive foreground/monochrome (108dp base) and legacy fallback (content 66%)
foreach ($d in $densities) {
    $dir = Join-Path $resDir ("mipmap-" + $d.Name)
    $fgSize = [int](108 * $d.Scale)
    $fgTarget = Join-Path $dir 'ic_launcher_foreground.png'
    $monoTarget = Join-Path $dir 'ic_launcher_monochrome.png'
    if ($fgSize -eq 432) {
        Copy-Item $ForegroundPath $fgTarget -Force
        Copy-Item $MonochromePath $monoTarget -Force
    } else {
        $b = New-TransparentScaled $fg $fgSize; Save-Png $b $fgTarget; $b.Dispose()
        $b = New-TransparentScaled $mono $fgSize; Save-Png $b $monoTarget; $b.Dispose()
    }

    $legacySize = [int](48 * $d.Scale)
    $b = New-Composite $fg $legacySize $lightBg 0.66 $box
    Save-Png $b (Join-Path $dir 'ic_launcher.png')
    $b.Dispose()
    Write-Host ("Android {0,-8} fg/mono={1} legacy={2}" -f $d.Name, $fgSize, $legacySize)
}

# 2) iOS: opaque full-bleed icons (content 72%, light background), one per Contents.json entry
$appIconDir = Join-Path $ProjectRoot 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
$contentsPath = Join-Path $appIconDir 'Contents.json'
if (!(Test-Path $contentsPath)) { throw "Missing iOS AppIcon Contents.json: $contentsPath" }
$contents = Get-Content $contentsPath -Raw | ConvertFrom-Json
foreach ($entry in $contents.images) {
    $parts = $entry.size -split 'x'
    $px = [double]$parts[0] * [double]$entry.scale.TrimEnd('x')
    $size = [int][Math]::Round($px)
    $b = New-Composite $fg $size $lightBg 0.72 $box
    Save-Png $b (Join-Path $appIconDir $entry.filename)
    $b.Dispose()
    Write-Host ("iOS {0,-28} {1}x{1}" -f $entry.filename, $size)
}
}

# 3) Windows: exe / taskbar / notification icon (same framing as iOS: light background, 72% content)
if (!$WindowsSourcePath) {
    $WindowsSourcePath = Join-Path $ProjectRoot 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher_foreground.png'
}
if (!(Test-Path $WindowsSourcePath)) {
    Write-Host "Windows source not found, falling back to the foreground path" -ForegroundColor DarkYellow
    $WindowsSourcePath = $ForegroundPath
}
$winSource = [System.Drawing.Bitmap]::FromFile($WindowsSourcePath)
$winBox = Get-ContentBox $winSource
$icoPath = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
$icoSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
# 22% 圆角：与微信 / QQ 图标观感一致，16px 下也还看得出圆角
Save-Ico $icoPath $winSource $lightBg 0.72 $winBox $icoSizes -RadiusFraction 0.22
$winSource.Dispose()
Write-Host ("Windows  {0,-28} {1} sizes, up to {2}px" -f 'app_icon.ico', $icoSizes.Count, 256)

$fg.Dispose(); $mono.Dispose()
Write-Host 'Icon generation finished.'
