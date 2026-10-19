<#
.SYNOPSIS
  本地一键发版：校验 → Android 构建 → Windows 构建 → GitHub Release。

.DESCRIPTION
  这个脚本只负责编排，四段实际逻辑分别在：
    tools/release/validate.ps1
    tools/release/build_android.ps1
    tools/release/build_windows.ps1
    tools/release/publish.ps1

  GitHub Actions 使用同一组子脚本，见 .github/workflows/release.yml。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/release.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/release.ps1 -Draft
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/release.ps1 -NotesFile docs/releases/26.1.0-snapshot.1.md
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/release.ps1 -DryRun
#>
[CmdletBinding()]
param(
  # 手写发布说明（markdown，格式见 docs/releases/TEMPLATE.md）；
  # 不传则优先用 docs/releases/<版本>.md，再回退到自动生成
  [string]$NotesFile = '',
  # 先建草稿，确认无误再到网页里发布
  [switch]$Draft,
  # 跳过 dart format 检查与 flutter analyze / test
  [switch]$SkipTests,
  # 跳过 Windows 便携版（默认一起构建并挂到 Release）
  [switch]$SkipWindows,
  # 跳过 Android APK（只发 Windows 时使用）
  [switch]$SkipAndroid,
  # 只做检查与打印，不构建、不打 tag、不发 Release
  [switch]$DryRun,
  # 期望的签名证书 SHA-256 指纹（应与 README「签名」一致）
  [string]$ExpectedCertSha256 =
    '70BD4AA85322FE26E67202FAC31729BDE1F854FA1BD2FD52C88FFCAA02EDB5BB'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Fail([string]$text) { throw $text }

if ($SkipAndroid -and $SkipWindows) {
  Fail 'Android 和 Windows 都被跳过了，没有可发布的产物'
}

$releaseDir = Join-Path $PSScriptRoot 'release'
$validateScript = Join-Path $releaseDir 'validate.ps1'
$androidScript = Join-Path $releaseDir 'build_android.ps1'
$windowsScript = Join-Path $releaseDir 'build_windows.ps1'
$publishScript = Join-Path $releaseDir 'publish.ps1'

foreach ($script in @(
  $validateScript, $androidScript, $windowsScript, $publishScript
)) {
  if (!(Test-Path -LiteralPath $script)) {
    Fail "找不到发布脚本：$script"
  }
}

Info '1/4 校验版本、代码与 Git 状态'
& $validateScript `
  -SkipTests:$($SkipTests.IsPresent) `
  -DryRun:$($DryRun.IsPresent) `
  -AllowDirty:$($DryRun.IsPresent) `
  -SkipAndroidTools:$($SkipAndroid.IsPresent) `
  -ExpectedCertSha256 $ExpectedCertSha256

Info '2/4 Android 构建'
if ($SkipAndroid) {
  Write-Host '（已跳过）' -ForegroundColor DarkYellow
} else {
  & $androidScript `
    -SkipTests `
    -SkipPubGet:$(!$SkipTests) `
    -DryRun:$($DryRun.IsPresent) `
    -ExpectedCertSha256 $ExpectedCertSha256
}

Info '3/4 Windows 构建'
if ($SkipWindows) {
  Write-Host '（已跳过）' -ForegroundColor DarkYellow
} else {
  & $windowsScript `
    -SkipTests `
    -SkipPubGet:$(!$SkipTests) `
    -DryRun:$($DryRun.IsPresent)
}

Info '4/4 创建 Release 并上传产物'
if ($NotesFile) {
  & $publishScript `
    -Draft:$($Draft.IsPresent) `
    -RequireAndroid:(!$SkipAndroid) `
    -RequireWindows:(!$SkipWindows) `
    -DryRun:$($DryRun.IsPresent) `
    -NotesFile $NotesFile
} else {
  & $publishScript `
    -Draft:$($Draft.IsPresent) `
    -RequireAndroid:(!$SkipAndroid) `
    -RequireWindows:(!$SkipWindows) `
    -DryRun:$($DryRun.IsPresent)
}

Info '完成'
