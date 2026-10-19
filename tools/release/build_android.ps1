<#
.SYNOPSIS
  构建 Android release APK（按 ABI 拆分），并校验发布签名。

.DESCRIPTION
  这是发布流程的第二段，只负责 Android 产物：

  - 可用时先跑 dart format / flutter analyze / flutter test
  - flutter build apk --release --split-per-abi
  - 复制为 LanCloud_android_<版本>_<ABI>.apk
  - 用 apksigner 校验证书 SHA-256，防止 CI 漏配签名时发出 debug 包

  签名材料由调用方准备：本地用 android/key.properties；CI 从 GitHub Secrets
  还原到 android/key.properties 与 android/app/ci-release.jks。

.EXAMPLE
  pwsh -File tools/release/build_android.ps1
.EXAMPLE
  pwsh -File tools/release/build_android.ps1 -SkipTests
#>
[CmdletBinding()]
param(
  # 跳过 dart format / flutter analyze / flutter test（校验阶段已跑过时使用）
  [switch]$SkipTests,
  # 跳过 flutter pub get（CI 已在前面执行过时可加）
  [switch]$SkipPubGet,
  # 只打印命令，不构建
  [switch]$DryRun,
  # 产物输出目录，默认 <repo>/outputs
  [string]$OutputDir = '',
  [string]$ExpectedCertSha256 =
    '70BD4AA85322FE26E67202FAC31729BDE1F854FA1BD2FD52C88FFCAA02EDB5BB'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1') -Force

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Fail([string]$text) { throw $text }

$root = Get-ProjectRoot -ScriptRoot $PSScriptRoot
Set-Location $root
$version = Get-ReleaseVersion -Root $root
Assert-FingerprintFormat -Fingerprint $ExpectedCertSha256

$flutter = Get-FlutterCommand -Root $root
$dart = Get-DartCommand -Root $root
$androidSdk = Get-AndroidSdk -Root $root
$apksigner = Get-ApkSigner -AndroidSdk $androidSdk

Info "LanCloud $($version.Name)（android，versionCode $($version.Code)）"

if (!$SkipPubGet) {
  Info 'flutter pub get'
  Invoke-ReleaseTool -Exe $flutter -Arguments @('pub', 'get') -DryRun:$DryRun
}

if (!$SkipTests) {
  Info 'dart format 检查'
  Invoke-ReleaseTool -Exe $dart -Arguments @(
    'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'
  ) -DryRun:$DryRun
  Info 'flutter analyze'
  Invoke-ReleaseTool -Exe $flutter -Arguments @('analyze') -DryRun:$DryRun
  Info 'flutter test'
  Invoke-ReleaseTool -Exe $flutter -Arguments @('test') -DryRun:$DryRun
}

# 构建信息注入「关于 - 构建信息」弹窗：构建时间 + 提交号
$buildTime = Format-BuildTime
$commitHash = if ($env:GITHUB_SHA) {
  $env:GITHUB_SHA
} else {
  Get-GitCommit -Root $root
}
Info "构建信息：$buildTime · $commitHash"

Info 'flutter build apk --release --split-per-abi'
Invoke-ReleaseTool -Exe $flutter -Arguments @(
  'build', 'apk', '--release', '--split-per-abi',
  "--dart-define=BUILD_TIME=$buildTime",
  "--dart-define=GIT_COMMIT=$commitHash"
) -DryRun:$DryRun

if (!$OutputDir) {
  $OutputDir = Join-Path $root 'outputs'
}
if (!$DryRun) {
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

$apkDir = Join-Path $root 'build/app/outputs/flutter-apk'
$assets = @()

foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
  $source = Join-Path $apkDir "app-$abi-release.apk"
  $destination = Join-Path $OutputDir "LanCloud_android_$($version.Name)_$abi.apk"
  if (!$DryRun) {
    if (!(Test-Path -LiteralPath $source)) {
      Fail "构建产物缺失：$source"
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
  }
  $assets += $destination
}

if (!$DryRun) {
  Info "校验签名指纹（$ExpectedCertSha256）"
  $certOutput = Invoke-ReleaseTool -Exe $apksigner -Arguments @(
    'verify', '--print-certs', $assets[0]
  ) -Capture -Quiet
  $certText = ($certOutput -join "`n")
  $certMatch = [regex]::Match($certText, 'SHA-256 digest:\s*([0-9a-fA-F]+)')
  if (!$certMatch.Success) {
    Fail 'apksigner 没有输出证书指纹'
  }
  $actual = $certMatch.Groups[1].Value.ToUpperInvariant()
  if ($actual -ne $ExpectedCertSha256.ToUpperInvariant()) {
    Fail "签名指纹不一致，可能漏配 key.properties（会退回 debug 签名）：`n  实际 $actual"
  }
  Info '签名指纹正确'

  $summaryRows = @()
  foreach ($asset in $assets) {
    $file = Get-Item -LiteralPath $asset
    $summaryRows += "| ``$($file.Name)`` | $([math]::Round($file.Length / 1MB, 2)) MB | ``$(Get-FileSha256 -Path $asset)`` |"
  }
  Add-CISummary @"
### Android 产物

| 文件 | 大小 | SHA-256 |
| --- | ---: | --- |
$($summaryRows -join "`n")
"@
}

Info 'Android 构建完成'
