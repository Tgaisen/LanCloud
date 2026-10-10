# Generates LanCloud app icons: Android adaptive icons (foreground/monochrome
# layers plus night background color), the iOS AppIcon set and the Windows .ico.
#
# 首选路径：用矢量母版 assets/icon_master.svg 在**每个目标尺寸**上单独栅格化
# （零缩放，小尺寸最锐），需要 node + @resvg/resvg-js：
#     npm i @resvg/resvg-js        # 装哪都行，用 NODE_PATH 指过来也可以
# 找不到就回退到"把 432px 前景层位图降采样"，能用，只是小尺寸略软。
#
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_app_icons.ps1
#        powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_app_icons.ps1 -WindowsOnly
#
# Icon spec（回退路径用这几份位图；矢量路径下同一份设计由 SVG 提供）:
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

# Writes an .ico made of pre-rendered PNG frames.
#
# Every frame is a PNG: it keeps the file small (16..256px ≈ 26KB instead of
# ~260KB of uncompressed 32bpp DIB frames) and Windows 10/11 read PNG frames at
# any size — Kazumi and other Flutter apps ship exactly that layout and render
# crisply, and the frames below are rendered from the vector per size, so the
# shell never has to rescale them.
function Write-Ico([string]$Path, [object[]]$Frames) {
    # 注意变量名别叫 $frames：PowerShell 变量名大小写不敏感，
    # 会直接覆盖参数 $Frames（踩过一次，ico 里会写出 0 帧）
    $entries = @()
    foreach ($f in $Frames) {
        # 每个 frame 是 [pscustomobject]@{ Size; Bytes }：对象不会被 PowerShell
        # 展开，避免"数组套数组"被拍平后写坏 ico
        $entries += , @([int]$f.Size, [byte[]]$f.Bytes)
    }
    $dir = Split-Path -Parent $Path
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    try {
        $bw.Write([UInt16]0)          # reserved
        $bw.Write([UInt16]1)          # type: 1 = icon
        $bw.Write([UInt16]$entries.Count)
        $offset = 6 + 16 * $entries.Count
        foreach ($f in $entries) {
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
        foreach ($f in $entries) { $bw.Write($f[1]) }
    } finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

function New-SvgRenderDir {
    Join-Path ([System.IO.Path]::GetTempPath()) ("lancloud_icon_" + [guid]::NewGuid().ToString('N'))
}

# Renders the master SVG (assets/icon_master.svg) at exact pixel sizes via
# tools/render_icon_pngs.cjs. Returns $false when node / @resvg/resvg-js are not
# available, so callers can fall back to downscaling a bitmap instead.
function Invoke-SvgRender(
    [string]$SvgPath,
    [string]$OutDir,
    [int[]]$Sizes,
    [string[]]$ExtraFlags = @()
) {
    if (!$script:nodeRenderer) { return $false }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & node $script:nodeRenderer $SvgPath $OutDir ($Sizes -join ',') @ExtraFlags 2>&1
        $exit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($exit -ne 0) {
        Write-Host '  node/resvg 渲染失败，回退到位图降采样：' -ForegroundColor DarkYellow
        $output | Select-Object -Last 3 | ForEach-Object { Write-Host "    $_" }
        return $false
    }
    foreach ($size in $Sizes) {
        if (!(Test-Path (Join-Path $OutDir "$size.png"))) { return $false }
    }
    return $true
}

# ICO frames（每个尺寸的 PNG 字节）来自 SVG；失败返回 $null
function New-IcoFramesFromSvg([string]$SvgPath, [int[]]$Sizes) {
    $outDir = New-SvgRenderDir
    if (!(Invoke-SvgRender $SvgPath $outDir $Sizes @('--crop-tile', '--fix-seams'))) { return $null }
    $frames = @()
    foreach ($size in $Sizes) {
        $frames += [pscustomobject]@{
            Size = $size
            Bytes = [System.IO.File]::ReadAllBytes((Join-Path $outDir "$size.png"))
        }
    }
    return $frames
}

# 把带 alpha 的 PNG 重新存成 24bpp 不透明 PNG（App Store 不接受带 alpha 通道的图标）
function ConvertTo-OpaquePng([string]$Path) {
    $src = [System.Drawing.Bitmap]::FromFile($Path)
    $opaque = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = New-Graphics $opaque
    $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
    $g.Dispose()
    $src.Dispose()
    $opaque.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $opaque.Dispose()
}

function Save-Ico([string]$Path, [System.Drawing.Image]$Src, [System.Drawing.Color]$Bg, [double]$ContentFraction, [hashtable]$Box, [int[]]$Sizes, [double]$RadiusFraction = 0) {
    # 位图降采样回退路径（没有 node/resvg 时用）
    $frames = @()
    foreach ($size in $Sizes) {
        if ($RadiusFraction -gt 0) {
            $b = New-RoundedComposite $Src $size $Bg $ContentFraction $Box $RadiusFraction
        } else {
            $b = New-Composite $Src $size $Bg $ContentFraction $Box
        }
        $ms = New-Object System.IO.MemoryStream
        $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $frames += [pscustomobject]@{ Size = $size; Bytes = $ms.ToArray() }
        $ms.Dispose()
        $b.Dispose()
    }
    Write-Ico $Path $frames
}

$fg = [System.Drawing.Bitmap]::FromFile($ForegroundPath)
$mono = [System.Drawing.Bitmap]::FromFile($MonochromePath)
if ($fg.Width -ne 432 -or $fg.Height -ne 432) { throw "Foreground must be 432x432, got $($fg.Width)x$($fg.Height)" }
if ($mono.Width -ne 432 -or $mono.Height -ne 432) { throw "Monochrome must be 432x432, got $($mono.Width)x$($mono.Height)" }

$box = Get-ContentBox $fg
Write-Host ("Foreground content box: w={0} h={1} ({2:P0} of the 432 canvas)" -f $box.Width, $box.Height, ($box.Width / 432.0))

$lightBg = Convert-ToColor $LightBackground
$lightBgHex = $LightBackground.TrimStart('#').ToUpper()
$resDir = Join-Path $ProjectRoot 'android\app\src\main\res'

# 图标母版（矢量）+ 渲染器：有 node 和 @resvg/resvg-js 时所有平台都直接用
# 矢量在目标尺寸上栅格化（最锐）；否则回退到 android 里那张 432px 前景层
# 位图降采样。
$masterSvg = Join-Path $ProjectRoot 'assets\icon_master.svg'
# 只有云朵、没有圆角方块的一层（自适应图标的前景 / 单色层用）。
# 方块的"背景色"由 Android 的 <background> 图层提供：浅色 #0AC4E0、
# 深色 #3E3E75（values / values-night），所以前景不该再画一遍方块，
# 否则深色模式会露出一块浅色的方块。
$masterFgSvg = Join-Path $ProjectRoot 'assets\icon_master_foreground.svg'
# 深色版整图（方块 #3E3E75 + 白云）：给需要"深色整图"的场合用
# （例如文档 / 预览图），Android 侧靠背景色切换，不需要它。
$masterDarkSvg = Join-Path $ProjectRoot 'assets\icon_master_dark.svg'
$script:nodeRenderer = $null
if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $masterSvg)) {
    $candidate = Join-Path $PSScriptRoot 'render_icon_pngs.cjs'
    if (Test-Path $candidate) { $script:nodeRenderer = $candidate }
}
if (!$script:nodeRenderer) {
    Write-Host '未找到 node / @resvg/resvg-js：图标将由 432px 前景层降采样生成' -ForegroundColor DarkYellow
}

$densities = @(
    @{ Name = 'mdpi';    Scale = 1.0 },
    @{ Name = 'hdpi';    Scale = 1.5 },
    @{ Name = 'xhdpi';   Scale = 2.0 },
    @{ Name = 'xxhdpi';  Scale = 3.0 },
    @{ Name = 'xxxhdpi'; Scale = 4.0 }
)

if (!$WindowsOnly) {
# 1) Android: adaptive foreground/monochrome (108dp base) and legacy fallback
foreach ($d in $densities) {
    $dir = Join-Path $resDir ("mipmap-" + $d.Name)
    $fgSize = [int](108 * $d.Scale)
    $fgTarget = Join-Path $dir 'ic_launcher_foreground.png'
    $monoTarget = Join-Path $dir 'ic_launcher_monochrome.png'
    $legacySize = [int](48 * $d.Scale)

    $tmp = New-SvgRenderDir
    # 前景 / 单色层都用"只有云朵"的母版：方块背景由 <background> 图层给，
    # 深浅色自动跟着 values(-night) 的背景色走
    $viaSvg =
        (Invoke-SvgRender $masterFgSvg (Join-Path $tmp 'fg') @($fgSize) @('--fix-seams')) -and
        (Invoke-SvgRender $masterFgSvg (Join-Path $tmp 'mono') @($fgSize) @('--fix-seams')) -and
        (Invoke-SvgRender $masterFgSvg (Join-Path $tmp 'legacy') @($legacySize) @('--fix-seams', '--bg', $lightBgHex))
    if ($viaSvg) {
        Copy-Item (Join-Path $tmp "fg\$fgSize.png") $fgTarget -Force
        Copy-Item (Join-Path $tmp "mono\$fgSize.png") $monoTarget -Force
        Copy-Item (Join-Path $tmp "legacy\$legacySize.png") (Join-Path $dir 'ic_launcher.png') -Force
    } else {
        # 回退：从 432px 前景层位图降采样
        if ($fgSize -eq 432) {
            Copy-Item $ForegroundPath $fgTarget -Force
            Copy-Item $MonochromePath $monoTarget -Force
        } else {
            $b = New-TransparentScaled $fg $fgSize; Save-Png $b $fgTarget; $b.Dispose()
            $b = New-TransparentScaled $mono $fgSize; Save-Png $b $monoTarget; $b.Dispose()
        }
        $b = New-Composite $fg $legacySize $lightBg 0.66 $box
        Save-Png $b (Join-Path $dir 'ic_launcher.png')
        $b.Dispose()
    }
    Write-Host ("Android {0,-8} fg/mono={1} legacy={2}" -f $d.Name, $fgSize, $legacySize)
}

# 2) iOS: opaque full-bleed icons, one per Contents.json entry
$appIconDir = Join-Path $ProjectRoot 'ios\Runner\Assets.xcassets\AppIcon.appiconset'
$contentsPath = Join-Path $appIconDir 'Contents.json'
if (!(Test-Path $contentsPath)) { throw "Missing iOS AppIcon Contents.json: $contentsPath" }
$contents = Get-Content $contentsPath -Raw | ConvertFrom-Json
foreach ($entry in $contents.images) {
    $parts = $entry.size -split 'x'
    $px = [double]$parts[0] * [double]$entry.scale.TrimEnd('x')
    $size = [int][Math]::Round($px)
    $tmp = New-SvgRenderDir
    if (Invoke-SvgRender $masterFgSvg $tmp @($size) @('--fix-seams', '--bg', $lightBgHex)) {
        $target = Join-Path $appIconDir $entry.filename
        Copy-Item (Join-Path $tmp "$size.png") $target -Force
        # App Store 不接受带 alpha 通道的图标
        ConvertTo-OpaquePng $target
    } else {
        $b = New-Composite $fg $size $lightBg 0.72 $box
        Save-Png $b (Join-Path $appIconDir $entry.filename)
        $b.Dispose()
    }
    Write-Host ("iOS {0,-28} {1}x{1}" -f $entry.filename, $size)
}
}

# 3) Windows: exe / taskbar / notification icon
$icoPath = Join-Path $ProjectRoot 'windows\runner\resources\app_icon.ico'
# 覆盖系统在各 DPI 下会点名的尺寸，尺寸齐全 shell 就不必缩放（缩放 = 边缘发虚）。
#   - 标题栏 / 通知区：SM_CXSMICON = 16 × dpi/96 → 16 / 20 / 24 / 28 / 32 / 40 / 48
#   - Alt+Tab、资源管理器大图标：SM_CXICON = 32 × dpi/96 → 32 / 40 / 48 / 56 / 64 / 80 / 96
#   - Win11 任务栏按钮图标固定按逻辑 24px 画 → 24 × dpi/96 = 30（125%）、
#     36（150%）、42（175%）、48（200%）、60（250%）—— 少 30 这一档时任务栏
#     会拿 28 / 32 缩放，125% 缩放下最明显（云朵边缘发糊）
$icoSizes = @(
    16, 20, 24, 28, 30, 32, 36, 40, 42, 48, 54, 56, 60, 64, 72, 80, 96, 128, 256
)
# 首选：直接用母版 SVG 在目标尺寸上栅格化（零缩放，小尺寸最锐）。
$svgFrames = if (Test-Path $masterSvg) { New-IcoFramesFromSvg $masterSvg $icoSizes } else { $null }
if ($svgFrames) {
    Write-Ico $icoPath $svgFrames
    Write-Host ("Windows  {0,-28} {1} sizes, rendered from assets/icon_master.svg" -f 'app_icon.ico', $icoSizes.Count)
} else {
    # 回退：没有 node / @resvg/resvg-js 时，用位图母图降采样（圆角 22%，
# 与微信 / QQ 图标观感一致）
    if (!$WindowsSourcePath) {
        $WindowsSourcePath = Join-Path $ProjectRoot 'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher_foreground.png'
    }
    if (!(Test-Path $WindowsSourcePath)) {
        Write-Host "Windows source not found, falling back to the foreground path" -ForegroundColor DarkYellow
        $WindowsSourcePath = $ForegroundPath
    }
    $winSource = [System.Drawing.Bitmap]::FromFile($WindowsSourcePath)
    $winBox = Get-ContentBox $winSource
    Save-Ico $icoPath $winSource $lightBg 0.72 $winBox $icoSizes -RadiusFraction 0.22
    $winSource.Dispose()
    Write-Host ("Windows  {0,-28} {1} sizes, up to {2}px" -f 'app_icon.ico', $icoSizes.Count, 256)
}

$fg.Dispose(); $mono.Dispose()
Write-Host 'Icon generation finished.'
