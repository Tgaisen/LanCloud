# LanCloud 代理统一入口
#
# 设计要点（改动前先读）：
#   1. 自己裁剪输出，只打印结论 + 末尾几行。这样调用方不需要 `| Select-Object -Last N`，
#      命令字符串因此永久稳定 —— ~/.codex/rules/default.rules 里的免批准规则就按这些
#      字符串整串匹配，命令一变就得加规则，规则文件会重新膨胀。
#   2. 一律带 --no-pub：隐式 pub get 又慢又需要联网，沙箱内会直接失败。
#   3. 动词是固定白名单。新增动词必须同时在 rules 文件里加一条，否则会弹批准。
#
# 用法：tools\agent.cmd <动词> [参数...]
#   analyze [文件...]   有未提交改动就只分析这些文件，否则全量
#   test    [文件...]   按未提交改动推断受影响的测试文件，推断不出则全量
#   format  [目录...]   格式化 Dart 代码，默认 lib test tool
#   gen                 gen-l10n
#   pubget              pub get（需要联网，会被沙箱拦，属预期）
#   build-apk [参数]    默认 --debug
#   install             安装 build 目录里最新的 apk 到设备
#   logcat              拉最近 500 行并筛 flutter 相关
#   devices / doctor / emulators / run ...   透传给 flutter

param(
  [Parameter(Position = 0)][string]$Verb = 'help',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

# PowerShell 的 -File 模式会把 `--debug` 绑定成脚本公共参数，而不是放进
# ValueFromRemainingArguments。这里显式还原，避免 Flutter 命令静默改用 release。
if ($PSBoundParameters.ContainsKey('Debug') -and $Rest -notcontains '--debug') {
  $Rest = @($Rest) + @('--debug')
}

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$tools   = $PSScriptRoot
$root    = Split-Path -Parent $tools
$flutter = Join-Path $tools 'flutter.cmd'
$dart    = 'C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe'
$adb     = 'C:\dev\android-sdk\platform-tools\adb.exe'
$script:ExitCode = 0

function Invoke-Flutter {
  param(
    [string[]]$FlutterArgs,
    [int]$Tail = 15,
    [switch]$OnlyIssues
  )
  $raw = & $flutter @FlutterArgs 2>&1
  $script:ExitCode = $LASTEXITCODE
  # PowerShell 5.1 会把原生程序的 stderr 包成 ErrorRecord，直接 Out-String 会带上
  # CategoryInfo 之类的噪音；这里逐项转成纯文本，再按行拆开。
  $flat = (@($raw | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
  }) -join "`n")
  $lines = ($flat -split "\r?\n") | Where-Object { $_ -match '\S' }
  if ($OnlyIssues) {
    $hits = $lines | Where-Object { $_ -match '(error|warning|info)\s+\u2022' }
    if ($hits) { $hits | Select-Object -First 40 | ForEach-Object { $_.Trim() } }
  }
  $lines | Select-Object -Last $Tail
  Write-Output "---- exit=$($script:ExitCode)"
}

function Invoke-Dart {
  param(
    [string[]]$DartArgs,
    [int]$Tail = 12
  )
  $raw = & $dart @DartArgs 2>&1
  $script:ExitCode = $LASTEXITCODE
  $flat = (@($raw | ForEach-Object {
    if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ }
  }) -join "`n")
  ($flat -split "\r?\n") |
    Where-Object { $_ -match '\S' } |
    Select-Object -Last $Tail
  Write-Output "---- exit=$($script:ExitCode)"
}

function Get-DirtyDart {
  $raw = & git -C $root status --porcelain -- lib test 2>$null
  $paths = foreach ($l in $raw) {
    if ($null -eq $l -or $l.Length -lt 4) { continue }
    $p = $l.Substring(3).Trim() -replace '^.* -> ', ''
    if ($p -match '\.dart$') { $p }
  }
  @($paths | Select-Object -Unique)
}

function Resolve-Tests {
  param([string[]]$Dirty)
  $testDir = Join-Path $root 'test'
  if (-not (Test-Path $testDir)) { return @() }
  $all = @(Get-ChildItem $testDir -Filter '*_test.dart' -File | Select-Object -ExpandProperty FullName)
  $picked = New-Object System.Collections.Generic.List[string]
  foreach ($d in $Dirty) {
    if ($d -like 'test*') {
      $full = Join-Path $root $d
      if (Test-Path $full) { $picked.Add($full) }
      continue
    }
    if ($d -notlike 'lib*') { continue }
    $base   = [System.IO.Path]::GetFileNameWithoutExtension($d)
    $needle = [System.IO.Path]::GetFileName($d)
    foreach ($t in $all) {
      if ($picked -contains $t) { continue }
      if ([System.IO.Path]::GetFileName($t) -eq "${base}_test.dart") { $picked.Add($t); continue }
      if (Select-String -Path $t -Pattern $needle -SimpleMatch -Quiet -ErrorAction SilentlyContinue) { $picked.Add($t) }
    }
  }
  @($picked | Select-Object -Unique)
}

switch ($Verb) {
  'analyze' {
    $targets = @($Rest | Where-Object { $_ })
    if (-not $targets) { $targets = Get-DirtyDart | Where-Object { $_ -like 'lib*' } }
    if ($targets.Count -gt 0) {
      Write-Output "增量分析 $($targets.Count) 个文件"
      Invoke-Flutter -FlutterArgs (@('analyze', '--no-pub') + $targets) -OnlyIssues -Tail 2
    } else {
      Write-Output '无未提交的 lib 改动，跑全量（冷缓存约 1 分钟）'
      Invoke-Flutter -FlutterArgs @('analyze', '--no-pub') -OnlyIssues -Tail 2
    }
  }
  'test' {
    $targets = @($Rest | Where-Object { $_ })
    if (-not $targets) { $targets = @(Resolve-Tests -Dirty @(Get-DirtyDart)) }
    if ($targets.Count -gt 0) {
      Write-Output "运行 $($targets.Count) 个受影响的测试文件"
      Invoke-Flutter -FlutterArgs (@('test', '--no-pub') + $targets) -Tail 12
    } else {
      Write-Output '推断不出受影响的测试文件，跑全量（约 1.5 分钟）'
      Invoke-Flutter -FlutterArgs @('test', '--no-pub') -Tail 12
    }
  }
  'format' {
    $targets = @($Rest | Where-Object { $_ })
    if ($targets.Count -eq 0) {
      $targets = @('lib', 'test', 'tool')
    }
    Invoke-Dart -DartArgs (@('format') + $targets) -Tail 12
  }
  'gen' {
    Invoke-Flutter -FlutterArgs @('gen-l10n') -Tail 6
  }
  'pubget' {
    Invoke-Flutter -FlutterArgs @('pub', 'get') -Tail 6
  }
  'build-apk' {
    # 平台、拆分等附加参数不能隐式切换到 Flutter 的 release 默认值：
    # 只有显式传入 debug/profile/release 时才沿用调用方模式，否则始终补 --debug。
    $extra = @($Rest | Where-Object { $_ })
    $hasBuildMode = @(
      $extra | Where-Object { $_ -in @('--debug', '--profile', '--release') }
    ).Count -gt 0
    if (-not $hasBuildMode) {
      $extra = @('--debug') + $extra
    }
    Invoke-Flutter -FlutterArgs ((@('build', 'apk', '--no-pub') + $extra)) -Tail 8
  }
  'install' {
    $apk = Get-ChildItem (Join-Path $root 'build\app\outputs\flutter-apk') -Filter '*.apk' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $apk) { Write-Output '没找到 apk，先跑 build-apk'; $script:ExitCode = 1; break }
    Write-Output "安装 $($apk.Name)"
    & $adb install -r -d $apk.FullName 2>&1 | Select-Object -Last 3
    $script:ExitCode = $LASTEXITCODE
    Write-Output "---- exit=$($script:ExitCode)"
  }
  'logcat' {
    & $adb logcat -d -t 500 2>&1 |
      Select-String -Pattern 'flutter|DioException|FormatException|Lanzou|SocketException|FATAL' |
      Select-Object -Last 30 | ForEach-Object { $_.Line }
    Write-Output "---- exit=$LASTEXITCODE"
  }
  'help' {
    Get-Content $PSCommandPath | Select-Object -First 22 | Where-Object { $_ -like '#*' } | ForEach-Object { $_ -replace '^#\s?', '' }
  }
  default {
    # 透传：devices / doctor / emulators / run 等（这些会弹一次批准）
    Invoke-Flutter -FlutterArgs (@($Verb) + @($Rest | Where-Object { $_ })) -Tail 20
  }
}

exit $script:ExitCode
