<#
.SYNOPSIS
  构建 Windows x64 桌面版，把产物复制到 outputs 并打成便携版 zip。

.DESCRIPTION
  这是发布流程的第三段。前置条件（缺一不可）：

    1. Visual Studio 2022 或更新版本（含独立 Build Tools），
       勾选「使用 C++ 的桌面开发」工作负载（含 Windows SDK 与 CMake）
    2. 系统「开发者模式」已打开；CI 管理员会话可跳过此检查
    3. NuGet CLI 在 PATH 中，或在默认用户目录中

.EXAMPLE
  pwsh -File tools/release/build_windows.ps1
.EXAMPLE
  pwsh -File tools/release/build_windows.ps1 -SkipTests -CI
#>
[CmdletBinding()]
param(
  # 跳过 dart format / flutter analyze / flutter test
  [switch]$SkipTests,
  # 跳过 flutter pub get（CI 已在前面执行过时可加）
  [switch]$SkipPubGet,
  # 只构建并复制产物，不打包 zip
  [switch]$SkipZip,
  # GitHub Actions 模式：管理员会话下允许跳过开发者模式检查
  [switch]$CI,
  # 只打印命令，不构建
  [switch]$DryRun,
  # 产物输出目录，默认 <repo>/outputs
  [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1') -Force

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Warn([string]$text) { Write-Host "!!! $text" -ForegroundColor DarkYellow }
function Fail([string]$text) { throw $text }

if (!(Test-WindowsHost)) {
  Fail 'Windows 构建只能在 Windows 上运行'
}

$root = Get-ProjectRoot -ScriptRoot $PSScriptRoot
Set-Location $root
$version = Get-ReleaseVersion -Root $root
$isCI = $CI -or (Test-IsCI)

# ---------------------------------------------------------------- 前置检查
$programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
$vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path -LiteralPath $vswhere)) {
  Fail @'
找不到 Visual Studio。安装 Visual Studio 2022 或更新版本（社区版即可）并在安装器里勾选
「使用 C++ 的桌面开发」（Desktop development with C++），例如：
  winget install --id Microsoft.VisualStudio.2022.Community --override "--wait --passive --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
'@
}
$vsPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null)
if (!$vsPath) {
  Fail 'Visual Studio 已安装，但缺少「使用 C++ 的桌面开发」工作负载，请在 Visual Studio Installer 里补装后重试。'
}
Info "Visual Studio：$vsPath"

# Flutter 构建带插件的桌面应用需要创建符号链接；开发者模式或管理员会话二选一。
$devMode = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)
if ($devMode -ne 1) {
  if ($isCI -and $isAdmin) {
    Warn 'GitHub Actions 管理员会话：跳过开发者模式检查'
  } else {
    Fail @'
系统「开发者模式」未打开：Flutter 构建带插件的桌面应用需要创建符号链接。
打开方式：设置 → 系统 → 开发者选项 → 开发人员模式；
或以管理员身份执行：
  reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v AllowDevelopmentWithoutDevLicense /d 1
'@
  }
}

$nuget = Find-Executable -Names @('nuget.exe', 'nuget')
if (!$nuget) {
  $fallback = Join-Path $env:LOCALAPPDATA 'Programs\nuget\nuget.exe'
  if (Test-Path -LiteralPath $fallback) {
    $env:PATH = "$(Split-Path -Parent $fallback);$env:PATH"
    $nuget = $fallback
  }
}
if (!$nuget) {
  Fail @'
PATH 里找不到 nuget.exe（flutter_inappwebview 的 Windows 构建会用它拉 WebView2 SDK）。
装到用户目录并加入 PATH（新开终端后生效）：
  New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\nuget" | Out-Null
  Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile "$env:LOCALAPPDATA\Programs\nuget\nuget.exe"
  [Environment]::SetEnvironmentVariable('PATH', "$env:PATH;$env:LOCALAPPDATA\Programs\nuget", 'User')
'@
}

Info "LanCloud $($version.Name)（windows-x64）"
$flutter = Get-FlutterCommand -Root $root
$dart = Get-DartCommand -Root $root

# ---------------------------------------------------------------- 检查与测试
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

# ---------------------------------------------------------------- 构建
$buildTime = Format-BuildTime
$commitHash = if ($env:GITHUB_SHA) {
  $env:GITHUB_SHA
} else {
  Get-GitCommit -Root $root
}
Info "构建信息：$buildTime · $commitHash"
Info 'flutter build windows --release'
Invoke-ReleaseTool -Exe $flutter -Arguments @(
  'build', 'windows', '--release',
  '--no-pub',
  "--dart-define=BUILD_TIME=$buildTime",
  "--dart-define=GIT_COMMIT=$commitHash"
) -DryRun:$DryRun

if (!$OutputDir) {
  $OutputDir = Join-Path $root 'outputs'
}
$bundleDir = Join-Path $root 'build/windows/x64/runner/Release'
if (!$DryRun -and !(Test-Path -LiteralPath $bundleDir)) {
  Fail "构建产物缺失：$bundleDir"
}
if (!$DryRun) {
  New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}

# 产物命名：LanCloud_平台_版本_架构（Windows 便携版带 _portable 后缀）
$pkgDir = Join-Path $OutputDir "LanCloud_windows_$($version.Name)_x64_portable"

if (!$DryRun -and (Test-Path -LiteralPath $pkgDir)) {
  $resolvedOutput = (Resolve-Path -LiteralPath $OutputDir).Path
  $resolved = (Resolve-Path -LiteralPath $pkgDir).Path
  $prefix = $resolvedOutput.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
  if (!$resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    Fail "拒绝删除 outputs 目录之外的路径：$resolved"
  }
  # 只有正在从目标目录运行的 LanCloud 才会占着产物里的 DLL；其他位置的
  # 已安装版本不影响本次打包。
  $running = Get-Process -Name 'lancloud' -ErrorAction SilentlyContinue |
    Where-Object {
      $processPath = $null
      try { $processPath = $_.Path } catch { }
      $processPath -and
        $processPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    }
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

if (!$DryRun) {
  New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
  # build\...\Release 是本机运行过 exe 的目录时，WebView2 会在旁边生成
  # lancloud.exe.WebView2 用户数据（缓存、Cookie 等，体积也可观）。
  # 它属于运行时数据，不能进便携包。
  $bundleItems = Get-ChildItem -LiteralPath $bundleDir -Force |
    Where-Object { $_.Name -notlike '*.WebView2' }
  foreach ($item in $bundleItems) {
    Copy-Item -LiteralPath $item.FullName -Destination $pkgDir -Recurse -Force
  }
  if (Get-ChildItem -LiteralPath $bundleDir -Force |
      Where-Object Name -like '*.WebView2') {
    Warn '已排除构建目录中的 *.WebView2 运行时数据'
  }

  # VC++ 运行时（app-local 部署）：目标机器不一定装过 VC++ Redistributable，
  # 而 exe 依赖 VCRUNTIME140 / MSVCP140，缺了会直接起不来。这里把 VS 里
  # 可再分发的那一套 DLL 拷到 exe 同目录，便携版才能"解压即用"。
  #
  # 必须从一个完整的最高版本目录复制。旧实现先跨所有版本收集文件再按
  # 文件名任取一个，在 CI Runner 同时装有多套 MSVC Redist 时会把 14.29、
  # 14.44、14.51 等版本混进同一个便携包，导致 WebView2 初始化时进程退出。
  $crtRoot = Join-Path $vsPath 'VC\Redist\MSVC'
  $crtSet = $null
  $crtVersionDirs = Get-ChildItem -LiteralPath $crtRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -match '^\d+(\.\d+)+$' |
    Sort-Object { [version]$_.Name } -Descending
  foreach ($versionDir in $crtVersionDirs) {
    $candidate = Get-ChildItem -LiteralPath (Join-Path $versionDir.FullName 'x64') `
      -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      Select-Object -First 1
    if ($candidate) {
      $crtSet = $candidate
      break
    }
  }
  $crtFiles = if ($crtSet) {
    @(Get-ChildItem -LiteralPath $crtSet.FullName -File -Filter '*.dll')
  } else {
    @()
  }
  $requiredCrtFiles = @(
    'msvcp140.dll',
    'vcruntime140.dll',
    'vcruntime140_1.dll'
  )
  $missingCrtFiles = @(
    $requiredCrtFiles | Where-Object {
      -not ($crtFiles.Name -contains $_)
    }
  )
  if ($crtFiles.Count -eq 0 -or $missingCrtFiles.Count -gt 0) {
    Fail '没找到完整的 VC++ 运行时可再分发副本，拒绝生成可能无法启动的便携包'
  } else {
    $copied = 0
    $bytes = 0
    foreach ($file in $crtFiles) {
      Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $pkgDir $file.Name) -Force
      $copied += 1
      $bytes += $file.Length
    }
    $versions = @(
      $crtFiles |
        ForEach-Object { $_.VersionInfo.FileVersion } |
        Where-Object { $_ } |
        Sort-Object -Unique
    )
    if ($versions.Count -ne 1) {
      Fail "VC++ 运行时版本不一致，拒绝打包：$($versions -join ', ')"
    }
    Info ("已内置 VC++ 运行时 {0}：{1} 个 DLL（{2:N1} MB）" -f $versions[0], $copied, ($bytes / 1MB))
  }
  Info "产物已复制：$pkgDir"
}

$zip = Join-Path $OutputDir "LanCloud_windows_$($version.Name)_x64_portable.zip"
if (!$SkipZip -and !$DryRun) {
  if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
  }
  # 连带目录一起压缩：解压出来是一个顶层文件夹，不会把 exe 和 data\ 散落开
  Compress-Archive -Path $pkgDir -DestinationPath $zip -CompressionLevel Optimal
  Info "已打包：$zip"

  $zipFile = Get-Item -LiteralPath $zip
  Add-CISummary @"
### Windows 产物

| 文件 | 大小 | SHA-256 |
| --- | ---: | --- |
| ``$($zipFile.Name)`` | $([math]::Round($zipFile.Length / 1MB, 2)) MB | ``$(Get-FileSha256 -Path $zip)`` |
"@
}

Info 'Windows 构建完成'
