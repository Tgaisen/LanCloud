<#
.SYNOPSIS
  构建 Windows 桌面版（x64），把产物复制到 outputs 并按需打包 zip。

.DESCRIPTION
  前置条件（缺一不可，脚本会先检查）：
    1. Visual Studio 2022（社区版即可）或 Build Tools 2022，
       勾选「使用 C++ 的桌面开发」工作负载（含 Windows SDK 与 CMake）
    2. 系统「开发者模式」已打开：Flutter 构建带插件的桌面应用需要创建符号链接
    3. NuGet CLI 在 PATH 中：flutter_inappwebview_windows 构建时用它拉 WebView2 SDK

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 -SkipTests -SkipZip
#>
[CmdletBinding()]
param(
  # 跳过 dart format / flutter analyze / flutter test
  [switch]$SkipTests,
  # 只构建并复制产物，不打包 zip
  [switch]$SkipZip
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Warn([string]$text) { Write-Host "!!! $text" -ForegroundColor DarkYellow }
function Fail([string]$text) { throw $text }

function Invoke-Tool {
  param([string]$Exe, [string[]]$Arguments)
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
    $output | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
    Fail("命令失败（exit $exitCode）：$Exe $($Arguments -join ' ')")
  }
  return $output
}

# ---------------------------------------------------------------- 前置检查

# 1) Visual Studio + C++ 桌面开发工作负载
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path $vswhere)) {
  Fail @'
找不到 Visual Studio。安装 Visual Studio 2022 社区版并在安装器里勾选
「使用 C++ 的桌面开发」（Desktop development with C++）：
  winget install --id Microsoft.VisualStudio.2022.Community --override "--wait --passive --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
'@
}
$vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null)
if (!$vsPath) {
  Fail 'Visual Studio 已安装，但缺少「使用 C++ 的桌面开发」工作负载，请在 Visual Studio Installer 里补装后重试。'
}
Info "Visual Studio：$vsPath"

# 2) 开发者模式（符号链接，Flutter 构建插件必需）
$devMode = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($devMode -ne 1) {
  Fail @'
系统「开发者模式」未打开：Flutter 构建带插件的桌面应用需要创建符号链接。
打开方式：设置 → 系统 → 开发者选项 → 开发人员模式；
或以管理员身份执行：
  reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1
'@
}

# 3) NuGet CLI（flutter_inappwebview_windows 构建依赖）
if (!(Get-Command nuget -ErrorAction SilentlyContinue)) {
  Fail @'
PATH 里找不到 nuget.exe（flutter_inappwebview 的 Windows 构建会用它拉 WebView2 SDK）。
装到用户目录并加入 PATH（新开终端后生效）：
  New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\nuget" | Out-Null
  Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile "$env:LOCALAPPDATA\Programs\nuget\nuget.exe"
  [Environment]::SetEnvironmentVariable('PATH', "$env:PATH;$env:LOCALAPPDATA\Programs\nuget", 'User')
'@
}

# ---------------------------------------------------------------- 版本与检查
# 版本名含预发布后缀（如 26.1.0-pre.2）；'+' 后面是 versionCode，不要
$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)\+').Matches[0].Groups[1].Value
Info "LanCloud $version（windows-x64）"

if (!(Get-Command flutter -ErrorAction SilentlyContinue)) { Fail '找不到 flutter 命令' }

if (!$SkipTests) {
  Info 'dart format 检查'
  Invoke-Tool 'dart' @(
    'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'
  ) | Out-Null
  Info 'flutter analyze'
  Invoke-Tool 'flutter' @('analyze') | Out-Null
  Info 'flutter test'
  Invoke-Tool 'flutter' @('test') | Out-Null
}

# ---------------------------------------------------------------- 构建
$buildTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$commitHash = (& git -C $root rev-parse HEAD).Trim()
Info "构建信息：$buildTime · $commitHash"
Info 'flutter build windows --release'
Invoke-Tool 'flutter' @(
  'build', 'windows', '--release',
  "--dart-define=BUILD_TIME=$buildTime",
  "--dart-define=GIT_COMMIT=$commitHash"
) | Out-Null

$bundleDir = Join-Path $root 'build\windows\x64\runner\Release'
if (!(Test-Path $bundleDir)) { Fail "构建产物缺失：$bundleDir" }

# ---------------------------------------------------------------- 复制 / 打包
$outDir = Join-Path $root 'outputs'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$pkgDir = Join-Path $outDir "LanCloud-$version-windows-x64"

if (Test-Path -LiteralPath $pkgDir) {
  $resolved = (Resolve-Path -LiteralPath $pkgDir).Path
  if (!$resolved.StartsWith($outDir, [StringComparison]::OrdinalIgnoreCase)) {
    Fail "拒绝删除 outputs 目录之外的路径：$resolved"
  }
  # 正在运行的 LanCloud 会占着产物里的 DLL，清理会失败：先给一句人话提示
  $running = Get-Process -Name 'lancloud' -ErrorAction SilentlyContinue
  if ($running) {
    $ids = ($running | ForEach-Object { $_.Id }) -join ', '
    Fail "还有正在运行的 LanCloud（PID $ids），先关掉再重试：$resolved"
  }
  try {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
  } catch {
    Fail "清理旧产物目录失败（可能仍被占用）：$resolved`n$_"
  }
}
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
Copy-Item -Path (Join-Path $bundleDir '*') -Destination $pkgDir -Recurse -Force

# VC++ 运行时（app-local 部署）：目标机器不一定装过 VC++ Redistributable，
# 而 exe 依赖 VCRUNTIME140 / MSVCP140，缺了会直接起不来。这里把 VS 里
# 可再分发的那套 DLL 拷到 exe 同目录，便携版才能"解压即用"。
$crtRoot = Join-Path $vsPath 'VC\Redist\MSVC'
$crtFiles = @(
  Get-ChildItem -Path (Join-Path $crtRoot '*\x64\Microsoft.VC*.CRT\*.dll') -ErrorAction SilentlyContinue
)
if ($crtFiles.Count -eq 0) {
  Warn '没找到 VC++ 运行时可再分发副本，产物在没装 Redistributable 的机器上可能无法启动'
} else {
  # v145 / 14.51 等目录可能指向同一套，按文件名去重
  $copied = 0
  $bytes = 0
  foreach ($group in ($crtFiles | Group-Object Name)) {
    $file = $group.Group | Select-Object -First 1
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $pkgDir $file.Name) -Force
    $copied += 1
    $bytes += $file.Length
  }
  Info ("已内置 VC++ 运行时：{0} 个 DLL（{1:N1} MB）" -f $copied, ($bytes / 1MB))
}
Info "产物已复制：$pkgDir"

if (!$SkipZip) {
  $zip = Join-Path $outDir "LanCloud-$version-windows-x64.zip"
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
  # 连带目录一起压缩：解压出来是 LanCloud-<版本>-windows-x64\ 一个文件夹，
  # 不会把 exe 和 data\ 散落到当前目录
  Compress-Archive -Path $pkgDir -DestinationPath $zip -CompressionLevel Optimal
  Info "已打包：$zip"
}

Info '完成'
