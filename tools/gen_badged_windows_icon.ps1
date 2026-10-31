# 从现有 Windows 图标逐帧生成 Profile / Debug 使用的 Code 角标图标。
#
# 图标底图仍来自 windows/runner/resources/app_icon.ico；Code 角标用矢量线条
# 在目标尺寸上直接绘制，不依赖第三方图像生成服务。基础图标重新生成后再次
# 运行本脚本即可同步角标版本：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\gen_badged_windows_icon.ps1
param(
    [string]$SourcePath = '',
    [string]$OutputPath = '',
    [string]$PreviewPath = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$projectRoot = Split-Path -Parent $PSScriptRoot
if (!$SourcePath) {
    $SourcePath = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
}
if (!$OutputPath) {
    $OutputPath = Join-Path $projectRoot 'windows\runner\resources\app_icon_badge.ico'
}
$SourcePath = [System.IO.Path]::GetFullPath($SourcePath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function New-Graphics([System.Drawing.Bitmap]$Bitmap) {
    $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality =
        [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode =
        [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode =
        [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    return $graphics
}

function Add-CodeBadge(
    [System.Drawing.Bitmap]$Bitmap,
    [System.Drawing.Graphics]$Graphics
) {
    $size = [Math]::Min($Bitmap.Width, $Bitmap.Height)
    if ($size -lt 8) { return }

    # Windows 底图已经是 Android adaptive icon 裁切后的 72dp 磁贴。
    # Android 角标位于 108dp 画布的 (63,63)..(89,89)，映射到 72dp 磁贴后
    # 约为画布的 (45,45)..(71,71)，不能直接沿用 108dp 的归一化坐标。
    $badgeSize = [Math]::Max(4.0, $size * 0.33)
    $right = $size * 0.04
    $bottom = $size * 0.04
    $left = $Bitmap.Width - $right - $badgeSize
    $top = $Bitmap.Height - $bottom - $badgeSize

    $penWidth = [Math]::Max(1.0, $badgeSize * 0.065)
    $pen = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::White,
        $penWidth
    )
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    try {
        $leftChevron = New-Object System.Drawing.Drawing2D.GraphicsPath
        $rightChevron = New-Object System.Drawing.Drawing2D.GraphicsPath
        try {
            $leftChevron.AddLines([System.Drawing.PointF[]]@(
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.34,
                    $top + $badgeSize * 0.45
                ),
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.09,
                    $top + $badgeSize * 0.675
                ),
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.34,
                    $top + $badgeSize * 0.90
                )
            ))
            $rightChevron.AddLines([System.Drawing.PointF[]]@(
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.66,
                    $top + $badgeSize * 0.45
                ),
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.91,
                    $top + $badgeSize * 0.675
                ),
                [System.Drawing.PointF]::new(
                    $left + $badgeSize * 0.66,
                    $top + $badgeSize * 0.90
                )
            ))
            $Graphics.DrawPath($pen, $leftChevron)
            $Graphics.DrawPath($pen, $rightChevron)
        } finally {
            $leftChevron.Dispose()
            $rightChevron.Dispose()
        }
    } finally {
        $pen.Dispose()
    }
}

function Write-Icon([string]$Path, [object[]]$Frames) {
    $directory = Split-Path -Parent $Path
    if (!(Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    $stream = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([UInt16]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]$Frames.Count)
        $offset = 6 + 16 * $Frames.Count
        foreach ($frame in $Frames) {
            $dimension = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
            $writer.Write([Byte]$dimension)
            $writer.Write([Byte]$dimension)
            $writer.Write([Byte]0)
            $writer.Write([Byte]0)
            $writer.Write([UInt16]1)
            $writer.Write([UInt16]32)
            $writer.Write([UInt32]$frame.Bytes.Length)
            $writer.Write([UInt32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $Frames) {
            $writer.Write($frame.Bytes)
        }
    } finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

$sourceBytes = [System.IO.File]::ReadAllBytes($SourcePath)
if ($sourceBytes.Length -lt 6 -or
    [BitConverter]::ToUInt16($sourceBytes, 0) -ne 0 -or
    [BitConverter]::ToUInt16($sourceBytes, 2) -ne 1) {
    throw "不是有效的 ICO 文件：$SourcePath"
}

$count = [BitConverter]::ToUInt16($sourceBytes, 4)
$frames = @()
$largestPreview = $null
for ($index = 0; $index -lt $count; $index++) {
    $entry = 6 + 16 * $index
    $width = if ($sourceBytes[$entry] -eq 0) { 256 } else { [int]$sourceBytes[$entry] }
    $height = if ($sourceBytes[$entry + 1] -eq 0) {
        256
    } else {
        [int]$sourceBytes[$entry + 1]
    }
    $length = [BitConverter]::ToUInt32($sourceBytes, $entry + 8)
    $imageOffset = [BitConverter]::ToUInt32($sourceBytes, $entry + 12)
    $pngBytes = New-Object byte[] $length
    [Array]::Copy($sourceBytes, $imageOffset, $pngBytes, 0, $length)
    if ($pngBytes.Length -lt 8 -or
        $pngBytes[0] -ne 0x89 -or
        $pngBytes[1] -ne 0x50 -or
        $pngBytes[2] -ne 0x4E -or
        $pngBytes[3] -ne 0x47) {
        throw "ICO 第 $index 帧不是 PNG，无法无损叠加角标"
    }

    $inputStream = New-Object System.IO.MemoryStream(
        ,$pngBytes
    )
    $sourceImage = [System.Drawing.Image]::FromStream($inputStream)
    try {
        $bitmap = New-Object System.Drawing.Bitmap(
            $width,
            $height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = New-Graphics $bitmap
        try {
            $graphics.DrawImage($sourceImage, 0, 0, $width, $height)
            Add-CodeBadge $bitmap $graphics
            if ($PreviewPath -and $width -ge 256) {
                $largestPreview = $bitmap.Clone()
            }
        } finally {
            $graphics.Dispose()
        }

        $outputStream = New-Object System.IO.MemoryStream
        try {
            $bitmap.Save(
                $outputStream,
                [System.Drawing.Imaging.ImageFormat]::Png
            )
            $frames += [pscustomobject]@{
                Size = $width
                Bytes = $outputStream.ToArray()
            }
        } finally {
            $outputStream.Dispose()
            $bitmap.Dispose()
        }
    } finally {
        $sourceImage.Dispose()
        $inputStream.Dispose()
    }
}

Write-Icon $OutputPath $frames
if ($PreviewPath -and $largestPreview) {
    $previewDirectory = Split-Path -Parent $PreviewPath
    if (!(Test-Path -LiteralPath $previewDirectory)) {
        New-Item -ItemType Directory -Force -Path $previewDirectory | Out-Null
    }
    $largestPreview.Save(
        $PreviewPath,
        [System.Drawing.Imaging.ImageFormat]::Png
    )
    $largestPreview.Dispose()
}

Write-Output ("生成 {0}（{1} 帧）" -f $OutputPath, $frames.Count)
