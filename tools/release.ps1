<#
.SYNOPSIS
  构建并按版本号规范发布 GitHub Release（预发布自动带 Pre-release 标记）。

.DESCRIPTION
  - 从 pubspec.yaml 读 version（如 26.1.0-snapshot.1+260101001）
  - 校验 versionCode 是否符合分段公式（与 test/version_test.dart 同一套规则）
  - 校验工作区干净、HEAD 已推送到 origin/main、tag 不存在
  - flutter analyze / flutter test / flutter build apk --release --split-per-abi
  - 用 apksigner 校验签名证书指纹（防止漏配 key.properties 时发出 debug 签名包）
  - 打 tag 并推送，再用 gh 创建 Release，上传 arm64 / v7a / x86_64 三个 APK

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
  # 手写发布说明（markdown）；不传则用 gh --generate-notes 自动生成
  [string]$NotesFile = '',
  # 先建草稿，确认无误再到网页里发布
  [switch]$Draft,
  # 跳过 dart format 检查与 flutter analyze / test
  [switch]$SkipTests,
  # 跳过 Windows 便携版（默认一起构建并挂到 Release）
  [switch]$SkipWindows,
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

function Invoke-Tool {
  param([string]$Exe, [string[]]$Arguments)
  if ($DryRun) {
    Write-Host ("[dry-run] {0} {1}" -f $Exe, ($Arguments -join ' ')) -ForegroundColor DarkGray
    return @()
  }
  # 工具（flutter/gradle）会把进度、镜像提示写到 stderr；Stop 模式下
  # PowerShell 会把它们当成终止错误，这里临时放宽，只按退出码判断成败。
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $Exe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($exitCode -ne 0) {
    $output | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
    Fail("命令失败（exit $exitCode）：$Exe $($Arguments -join ' ')")
  }
  return $output
}

function Get-VersionCode([string]$name) {
  $release = [regex]::Match($name, '^(\d{2})\.(\d+)\.(\d+)$')
  if ($release.Success) {
    return [int]$release.Groups[1].Value * 10000000 +
           [int]$release.Groups[2].Value * 100000 +
           [int]$release.Groups[3].Value * 10000 +
           9 * 1000 + 999
  }
  $pre = [regex]::Match(
    $name, '^(\d{2})\.(\d+)\.(\d+)-(snapshot|pre|beta|rc)\.(\d+)$')
  if (-not $pre.Success) { return $null }
  $stage = switch ($pre.Groups[4].Value) {
    'snapshot' { 1 }
    'pre' { 2 }
    'beta' { 2 }
    'rc' { 3 }
  }
  return [int]$pre.Groups[1].Value * 10000000 +
         [int]$pre.Groups[2].Value * 100000 +
         [int]$pre.Groups[3].Value * 10000 +
         $stage * 1000 +
         [int]$pre.Groups[5].Value
}

# ---------------------------------------------------------------- 版本号
$pubspecPath = Join-Path $root 'pubspec.yaml'
$versionLine = Get-Content $pubspecPath |
  Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
if (-not $versionLine) { Fail 'pubspec.yaml 里找不到 version:' }
$versionRaw = ($versionLine -replace '^version:\s*', '').Trim()
$vm = [regex]::Match($versionRaw, '^([^+\s]+)\+(\d+)$')
if (-not $vm.Success) {
  Fail "pubspec.yaml 的 version 需要写成 版本号+versionCode，当前是 $versionRaw"
}
$versionName = $vm.Groups[1].Value
$versionCode = [int]$vm.Groups[2].Value
$expectedCode = Get-VersionCode $versionName
if ($null -eq $expectedCode) {
  Fail "版本号不符合规范（见 README「版本号规范」）：$versionName"
}
if ($versionCode -ne $expectedCode) {
  Fail "versionCode 与公式不一致：应为 $expectedCode，pubspec 写的是 $versionCode"
}
$isPreRelease = $versionName.Contains('-')
$tag = "v$versionName"

Info "版本号 $versionName（versionCode $versionCode，$(if ($isPreRelease) { '预发布' } else { '正式版' })）"
Info "tag：$tag"

# ---------------------------------------------------------------- git 状态
$dirty = & git -C $root status --porcelain
if ($dirty) {
  if ($DryRun) {
    Write-Host '（dry-run）工作区有未提交改动，已跳过检查' -ForegroundColor DarkYellow
  } else {
    Fail '工作区不干净，先把改动提交再发版'
  }
}
$head = (& git -C $root rev-parse HEAD).Trim()
$remoteLine = (& git -C $root ls-remote origin refs/heads/main) -join ''
$remoteSha = ($remoteLine -split '\s+')[0]
if ($head -ne $remoteSha) { Fail '本地 HEAD 还没推送到 origin/main，先 git push' }
if (& git -C $root tag -l $tag) { Fail "本地已存在 tag $tag" }
if (& git -C $root ls-remote --tags origin "refs/tags/$tag") {
  Fail "远端已存在 tag $tag"
}
Info "git 状态正常（$($head.Substring(0, 7)) 已推送）"

# ---------------------------------------------------------------- 工具路径
$localProps = Join-Path $root 'android\local.properties'
$sdkDir = $env:ANDROID_HOME
$flutterSdk = ''
if (Test-Path $localProps) {
  foreach ($line in Get-Content $localProps) {
    if ($line -match '^sdk\.dir=(.+)$') { $sdkDir = $Matches[1].Trim() }
    if ($line -match '^flutter\.sdk=(.+)$') { $flutterSdk = $Matches[1].Trim() }
  }
}
if (-not $sdkDir) { $sdkDir = $env:ANDROID_SDK_ROOT }
if (-not $sdkDir) { Fail '找不到 Android SDK，请设置 ANDROID_HOME 或 local.properties 的 sdk.dir' }

$flutter = if ($flutterSdk) {
  Join-Path $flutterSdk 'bin\flutter.bat'
} else {
  (Get-Command flutter -ErrorAction SilentlyContinue).Source
}
if (-not $flutter -or -not (Test-Path $flutter)) { Fail '找不到 flutter 命令' }
$dart = Join-Path (Split-Path -Parent $flutter) 'dart.bat'
if (-not (Test-Path $dart)) { $dart = 'dart' }

$buildTools = Get-ChildItem (Join-Path $sdkDir 'build-tools') -Directory |
  Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if (-not $buildTools) { Fail '找不到 build-tools' }
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'

$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }
if (-not (Test-Path $gh)) { Fail '找不到 gh，请先安装 GitHub CLI（winget install GitHub.cli）' }
if (-not $DryRun) {
  $auth = & $gh auth status 2>&1
  if ($LASTEXITCODE -ne 0) {
    Fail "gh 还没登录，先执行：`n  & '$gh' auth login"
  }
}

# ---------------------------------------------------------------- 检查与构建
if (-not $SkipTests) {
  Info 'dart format 检查'
  Invoke-Tool $dart @(
    'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'
  ) | Out-Null
  Info 'flutter analyze'
  Invoke-Tool $flutter @('analyze') | Out-Null
  Info 'flutter test'
  Invoke-Tool $flutter @('test') | Out-Null
}

Info 'flutter build apk --release --split-per-abi'
# 构建信息注入「关于 - 构建信息」弹窗：构建时间 + 提交号
$buildTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$commitRaw = Invoke-Tool 'git' @('-C', $root, 'rev-parse', 'HEAD')
$commitHash = if ($commitRaw) { ($commitRaw | Select-Object -First 1).Trim() } else { '' }
Info "构建信息：$buildTime · $commitHash"
Invoke-Tool $flutter @(
  'build', 'apk', '--release', '--split-per-abi',
  "--dart-define=BUILD_TIME=$buildTime",
  "--dart-define=GIT_COMMIT=$commitHash"
) | Out-Null

$apkDir = Join-Path $root 'build\app\outputs\flutter-apk'
$assets = @()
foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
  $src = Join-Path $apkDir "app-$abi-release.apk"
  # 产物命名：lanCloud_平台_版本_架构
  $dst = Join-Path $apkDir "lanCloud_android_${versionName}_$abi.apk"
  if (-not $DryRun) {
    if (-not (Test-Path $src)) { Fail "构建产物缺失：$src" }
    Copy-Item -LiteralPath $src -Destination $dst -Force
  }
  $assets += $dst
}

# ---------------------------------------------------------------- Windows 便携版
if (-not $SkipWindows) {
  Info 'tools/build_windows.ps1（Windows x64 绿色便携版）'
  # 复用构建脚本：前置检查（VS / 开发者模式 / NuGet）、构建、内置 VC++ 运行时、
  # 打成带顶层目录的 zip 都在里面；检查项上面刚跑过，这里 -SkipTests
  $winScript = Join-Path $PSScriptRoot 'build_windows.ps1'
  if (!(Test-Path $winScript)) { Fail "找不到构建脚本：$winScript" }
  if ($DryRun) {
    Write-Host ("[dry-run] powershell -File {0} -SkipTests" -f $winScript) `
      -ForegroundColor DarkGray
  } else {
    Invoke-Tool 'powershell' @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $winScript, '-SkipTests'
    ) | Out-Null
  }
  $winZip = Join-Path $root "outputs\lanCloud_windows_${versionName}_x64.zip"
  if (-not $DryRun -and !(Test-Path $winZip)) { Fail "构建产物缺失：$winZip" }
  $assets += $winZip
}

# ---------------------------------------------------------------- 签名校验
if (-not $DryRun) {
  Info "校验签名指纹（$ExpectedCertSha256）"
  $certs = (Invoke-Tool $apksigner @('verify', '--print-certs', $assets[0])) -join "`n"
  $certMatch = [regex]::Match($certs, 'SHA-256 digest:\s*([0-9a-fA-F]+)')
  if (-not $certMatch.Success) { Fail 'apksigner 没有输出证书指纹' }
  $actual = $certMatch.Groups[1].Value.ToUpper()
  if ($actual -ne $ExpectedCertSha256.ToUpper()) {
    Fail "签名指纹不一致，可能漏配 key.properties（会退回 debug 签名）：`n  实际 $actual"
  }
  Info '签名指纹正确'
}

# ---------------------------------------------------------------- 发布
if ($DryRun) {
  Info 'dry-run 结束：未打 tag、未创建 Release'
  return
}

Info "打 tag 并推送：$tag"
Invoke-Tool 'git' @('-C', $root, 'tag', '-a', $tag, '-m', $versionName) | Out-Null
Invoke-Tool 'git' @('-C', $root, 'push', 'origin', $tag) | Out-Null

$releaseArgs = @('release', 'create', $tag, '--verify-tag', '--title', $versionName)
if ($isPreRelease) { $releaseArgs += '--prerelease' }
if ($Draft) { $releaseArgs += '--draft' }
if ($NotesFile) {
  $notesPath = if ([System.IO.Path]::IsPathRooted($NotesFile)) {
    $NotesFile
  } else {
    Join-Path $root $NotesFile
  }
  if (-not (Test-Path $notesPath)) { Fail "找不到发布说明文件：$notesPath" }
  $releaseArgs += @('--notes-file', $notesPath)
} else {
  $releaseArgs += '--generate-notes'
}
$releaseArgs += $assets

Info "创建 Release：$tag"
Invoke-Tool $gh $releaseArgs | ForEach-Object { Write-Host $_ }

Info '完成'
