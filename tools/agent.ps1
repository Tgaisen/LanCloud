# LanCloud 代理统一入口
#
# 设计要点（改动前先读）：
#   1. 自己裁剪输出，只打印结论 + 末尾几行。这样调用方不需要 `| Select-Object -Last N`，
#      命令字符串因此永久稳定 —— ~/.codex/rules/default.rules 里的免批准规则就按这些
#      字符串整串匹配，命令一变就得加规则，规则文件会重新膨胀。
#   2. 一律带 --no-pub：隐式 pub get 又慢又需要联网，沙箱内会直接失败。
#   3. 动词是固定白名单。新增动词必须同时在 rules 文件里加一条，否则会弹批准。
#   4. build-* 只做原始编译；package-* 生成可分发产物并写入 outputs。
#
# 用法：tools\agent.cmd <动词> [参数...]
#   analyze [文件...]   有未提交改动就只分析这些文件，否则全量
#   test    [文件...]   按未提交改动推断受影响的测试文件，推断不出则全量
#   format  [目录...]   格式化 Dart 代码，默认 lib test tool
#   gen-l10n           生成本地化代码
#   pub-get             pub get（需要联网，会被沙箱拦，属预期）
#   build-android [参数] 默认 --debug 并拆 ABI；--install 构建后安装，--universal 不拆
#   build-windows [参数] 直接编译 Windows 应用，默认 --debug
#   package-android     正式拆 ABI 构建并校验 release 签名
#   package-windows     正式构建 Windows x64 便携版
#   install-build-android   把 build 目录中匹配设备 ABI 的 APK 装到设备
#   install-package-android 把 outputs 中匹配设备 ABI 的 APK 装到设备
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

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$tools   = $PSScriptRoot
$root    = Split-Path -Parent $tools
Import-Module (Join-Path $tools 'toolchain.psm1') -Force
$toolchain = Get-LanCloudToolchain
$flutter = $toolchain.Flutter
$dart = $toolchain.Dart
$adb = $toolchain.Adb
$powershell = (Get-Process -Id $PID).Path
$ErrorActionPreference = 'Continue'
$script:ExitCode = 0

function Invoke-Flutter {
  param(
    [string[]]$FlutterArgs,
    [int]$Tail = 15,
    [int]$FailureTail = 160,
    [switch]$OnlyIssues,
    [switch]$FailureDetails
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
    $hits = $lines | Where-Object {
      $_ -match '(error|warning|info)\s+(?:\u2022|-)\s+'
    }
    if ($hits) { $hits | Select-Object -First 300 | ForEach-Object { $_.Trim() } }
  }
  if ($script:ExitCode -ne 0 -and $FailureDetails) {
    $lineArray = @($lines)
    $indexes = New-Object System.Collections.Generic.List[int]
    $pattern = '(^e:\s|error:|FAILURE:|What went wrong|Execution failed|Caused by:|Unresolved reference|Compilation error|Exception:|Could not (resolve|find)|BUILD FAILED)'
    for ($i = 0; $i -lt $lineArray.Count; $i++) {
      if ($lineArray[$i] -notmatch $pattern) { continue }
      $from = [Math]::Max(0, $i - 2)
      $to = [Math]::Min($lineArray.Count - 1, $i + 6)
      for ($j = $from; $j -le $to; $j++) {
        if ($indexes -notcontains $j) { $indexes.Add($j) }
      }
    }
    if ($indexes.Count -gt 0) {
      Write-Output '---- failure details ----'
      $indexes.Sort()
      foreach ($index in $indexes) { $lineArray[$index] }
    }
  }
  $effectiveTail =
    if ($script:ExitCode -ne 0 -and $FailureDetails) {
      [Math]::Max($Tail, $FailureTail)
    } else {
      $Tail
    }
  $lines | Select-Object -Last $effectiveTail
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

function Invoke-ProjectScript {
  param(
    [string]$Path,
    [string[]]$ScriptArgs,
    [int]$Tail = 160
  )
  if (!(Test-Path -LiteralPath $Path)) {
    Write-Output "找不到脚本：$Path"
    $script:ExitCode = 1
    return
  }
  $raw = & $powershell -NoProfile -ExecutionPolicy Bypass -File $Path @ScriptArgs 2>&1
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
  $raw = & git -C $root status --porcelain --untracked-files=all -- lib test 2>$null
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
  $all = @(Get-ChildItem $testDir -Filter '*_test.dart' -File -Recurse |
    Select-Object -ExpandProperty FullName)
  $picked = New-Object System.Collections.Generic.List[string]
  foreach ($d in $Dirty) {
    if ($d -like 'test*') {
      $full = Join-Path $root $d
      foreach ($t in $all) {
        if ($picked -contains $t) { continue }
        if ($t -eq $full) { $picked.Add($t); continue }
        $needle = [System.IO.Path]::GetFileName($d)
        if (Select-String -Path $t -Pattern $needle -SimpleMatch -Quiet -ErrorAction SilentlyContinue) {
          $picked.Add($t)
        }
      }
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

function Resolve-BuildArgs {
  param([string[]]$Arguments)
  $extra = @($Arguments | Where-Object { $_ })
  $hasBuildMode = @(
    $extra | Where-Object { $_ -in @('--debug', '--profile', '--release') }
  ).Count -gt 0
  if (-not $hasBuildMode) {
    $extra = @('--debug') + $extra
  }
  @($extra)
}

function Resolve-AndroidBuildArgs {
  param([string[]]$Arguments)
  $universal = $Arguments -contains '--universal'
  $filtered = @(
    $Arguments |
      Where-Object { $_ -notin @('--install', '--universal') }
  )
  $extra = @(Resolve-BuildArgs -Arguments $filtered)
  if ($universal) {
    return @($extra | Where-Object { $_ -ne '--split-per-abi' })
  }
  if ($extra -notcontains '--split-per-abi') {
    $extra += '--split-per-abi'
  }
  @($extra)
}

function Add-BuildTimeArg {
  param([string[]]$Arguments)
  $filtered = @(
    $Arguments |
      Where-Object { $_ -notlike '--dart-define=BUILD_TIME=*' }
  )
  $buildTime = [DateTime]::UtcNow.ToString(
    "yyyy-MM-dd'T'HH:mm:ss'Z'",
    [System.Globalization.CultureInfo]::InvariantCulture
  )
  @($filtered + "--dart-define=BUILD_TIME=$buildTime")
}

function Show-Help {
  $lines = Get-Content $PSCommandPath
  $inUsage = $false
  foreach ($line in $lines) {
    if ($line -eq '# 用法：tools\agent.cmd <动词> [参数...]') {
      $inUsage = $true
    }
    if (!$inUsage) {
      continue
    }
    if ($line -notlike '#*') {
      break
    }
    $line -replace '^#\s?', ''
  }
}

function Get-ApkAbi {
  param([string]$Name)
  foreach ($abi in @('arm64-v8a', 'armeabi-v7a', 'x86_64')) {
    if ($Name -match [regex]::Escape($abi)) {
      return $abi
    }
  }
  return $null
}

function Resolve-DeviceApkAbi {
  param([string]$Abi)
  switch -Regex ($Abi.ToLowerInvariant()) {
    '^arm64' { return 'arm64-v8a' }
    '^armeabi' { return 'armeabi-v7a' }
    '^x86_64' { return 'x86_64' }
    default { return $null }
  }
}

function Select-CompatibleApk {
  param(
    [object[]]$Candidates,
    [string]$Abi
  )
  $specific = @(
    $Candidates |
      Where-Object { (Get-ApkAbi -Name $_.Name) -eq $Abi } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
  )
  $universal = @(
    $Candidates |
      Where-Object { !(Get-ApkAbi -Name $_.Name) } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
  )
  if ($specific.Count -eq 0) {
    if ($universal.Count -gt 0) {
      return $universal[0]
    }
    return $null
  }
  if ($universal.Count -eq 0 -or
      $specific[0].LastWriteTime -ge $universal[0].LastWriteTime) {
    return $specific[0]
  }
  return $universal[0]
}

function Install-AndroidApks {
  param(
    [ValidateSet('build', 'package')][string]$Source,
    [switch]$DryRun,
    [datetime]$Since = [datetime]::MinValue
  )
  if (!$adb) {
    Write-Output '找不到 adb；检查 C:\dev\android-sdk\platform-tools\adb.exe'
    $script:ExitCode = 1
    return
  }

  if ($Source -eq 'build') {
    $apkDir = Join-Path $root 'build\app\outputs\flutter-apk'
    $candidates = @(Get-ChildItem -LiteralPath $apkDir -File -Filter '*.apk' -ErrorAction SilentlyContinue)
    $sourceLabel = 'build'
    if ($Since -gt [datetime]::MinValue) {
      $builtCandidates = @(
        $candidates |
          Where-Object { $_.LastWriteTime -ge $Since.AddSeconds(-2) }
      )
      if ($builtCandidates.Count -gt 0) {
        $candidates = $builtCandidates
        $sourceLabel = '本次 build'
      }
    }
  } else {
    $apkDir = Join-Path $root 'outputs'
    $versionText = Get-Content -Raw -LiteralPath (Join-Path $root 'pubspec.yaml')
    $versionMatch = [regex]::Match($versionText, '(?m)^version:\s*([^+\s]+)\+')
    if (!$versionMatch.Success) {
      Write-Output '无法从 pubspec.yaml 读取当前版本号'
      $script:ExitCode = 1
      return
    }
    $version = $versionMatch.Groups[1].Value
    $prefix = "LanCloud_android_${version}_"
    $candidates = @(
      Get-ChildItem -LiteralPath $apkDir -File -Filter '*.apk' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }
    )
    $sourceLabel = "outputs（$version）"
  }

  if ($candidates.Count -eq 0) {
    $action = if ($Source -eq 'build') { 'build-android' } else { 'package-android' }
    Write-Output "找不到可安装的 APK；先运行 $action"
    $script:ExitCode = 1
    return
  }

  $rawDevices = & $adb devices 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Output 'adb devices 执行失败'
    $script:ExitCode = 1
    return
  }
  $devices = @(
    $rawDevices |
      ForEach-Object {
        if ($_.ToString() -match '^(\S+)\s+device(?:\s|$)') {
          $Matches[1]
        }
      }
  )
  if ($devices.Count -eq 0) {
    Write-Output '没有已授权的 Android 设备'
    $script:ExitCode = 1
    return
  }

  foreach ($serial in $devices) {
    $rawAbi = (& $adb -s $serial shell getprop ro.product.cpu.abi 2>$null | Out-String).Trim()
    if (!$rawAbi) {
      $rawAbi = (& $adb -s $serial shell getprop ro.product.cpu.abilist 2>$null |
        Out-String).Trim().Split(',')[0]
    }
    $deviceAbi = Resolve-DeviceApkAbi -Abi $rawAbi
    if (!$deviceAbi) {
      Write-Output "跳过 $serial：不支持的 ABI $rawAbi（当前只提供 arm64-v8a / armeabi-v7a / x86_64）"
      $script:ExitCode = 1
      continue
    }

    $apk = Select-CompatibleApk -Candidates $candidates -Abi $deviceAbi
    if (!$apk) {
      Write-Output "设备 $serial（$deviceAbi）在 $sourceLabel 中没有兼容 APK"
      $script:ExitCode = 1
      continue
    }
    $relative = $apk.FullName.Substring($root.Length).TrimStart('\')
    if ($DryRun) {
      Write-Output "[dry-run] $serial（$deviceAbi）← $relative"
      continue
    }

    Write-Output "安装 $relative 到 $serial（$deviceAbi）"
    $installOutput = @(& $adb -s $serial install -r -d $apk.FullName 2>&1)
    $installExit = $LASTEXITCODE
    $installOutput | Select-Object -Last 3
    if ($installExit -ne 0) {
      Write-Output "安装失败：$serial（exit $installExit）"
      $script:ExitCode = 1
    }
  }
}

switch ($Verb) {
  'analyze' {
    $targets = @($Rest | Where-Object { $_ })
    if (-not $targets) { $targets = Get-DirtyDart | Where-Object { $_ -like 'lib*' } }
    if ($targets.Count -gt 0) {
      Write-Output "增量分析 $($targets.Count) 个文件"
      Invoke-Flutter -FlutterArgs (@('analyze', '--fatal-infos', '--no-pub') + $targets) -OnlyIssues -Tail 2
    } else {
      Write-Output '无未提交的 lib 改动，跑全量（冷缓存约 1 分钟）'
      Invoke-Flutter -FlutterArgs @('analyze', '--fatal-infos', '--no-pub') -OnlyIssues -Tail 2
    }
  }
  'test' {
    $targets = @($Rest | Where-Object { $_ })
    if (-not $targets) { $targets = @(Resolve-Tests -Dirty @(Get-DirtyDart)) }
    # Windows 命令行长度有限；宽改动的绝对路径列表可能超过上限，
    # 在这种情况下直接跑全量，避免 cmd.exe 在 Flutter 启动前就报语法错误。
    if ($targets.Count -gt 60) {
      Write-Output "受影响测试文件过多（$($targets.Count) 个），跑全量（约 1.5 分钟）"
      Invoke-Flutter -FlutterArgs @('test', '--no-pub') -Tail 16 -FailureDetails
    } elseif ($targets.Count -gt 0) {
      Write-Output "运行 $($targets.Count) 个受影响的测试文件"
      Invoke-Flutter -FlutterArgs (@('test', '--no-pub') + $targets) -Tail 16 -FailureDetails
    } else {
      Write-Output '推断不出受影响的测试文件，跑全量（约 1.5 分钟）'
      Invoke-Flutter -FlutterArgs @('test', '--no-pub') -Tail 16 -FailureDetails
    }
  }
  'format' {
    $targets = @($Rest | Where-Object { $_ })
    if ($targets.Count -eq 0) {
      $targets = @('lib', 'test', 'tool')
    }
    Invoke-Dart -DartArgs (@('format') + $targets) -Tail 12
  }
  'gen-l10n' {
    Invoke-Flutter -FlutterArgs (@('gen-l10n') + @($Rest | Where-Object { $_ })) -Tail 6
  }
  'pub-get' {
    Invoke-Flutter -FlutterArgs (@('pub', 'get') + @($Rest | Where-Object { $_ })) -Tail 6
  }
  'build-android' {
    $rawArgs = @($Rest | Where-Object { $_ })
    $installAfterBuild = $rawArgs -contains '--install'
    $showHelp = $rawArgs -contains '--help' -or $rawArgs -contains '-h'
    $buildArgs = @(Resolve-AndroidBuildArgs -Arguments $rawArgs)
    $buildArgs = @(Add-BuildTimeArg -Arguments $buildArgs)
    $buildStartedAt = Get-Date
    Invoke-Flutter -FlutterArgs (@('build', 'apk', '--no-pub') + $buildArgs) -Tail 20 -FailureDetails
    if ($installAfterBuild -and !$showHelp -and $script:ExitCode -eq 0) {
      Install-AndroidApks -Source build -Since $buildStartedAt
    }
  }
  'build-windows' {
    $buildArgs = @(Resolve-BuildArgs -Arguments $Rest)
    $buildArgs = @(Add-BuildTimeArg -Arguments $buildArgs)
    Invoke-Flutter -FlutterArgs (@('build', 'windows', '--no-pub') + $buildArgs) -Tail 20 -FailureDetails
  }
  'package-android' {
    $scriptArgs = @($Rest | Where-Object { $_ })
    if ($scriptArgs -notcontains '-SkipPubGet') {
      $scriptArgs += '-SkipPubGet'
    }
    Invoke-ProjectScript `
      -Path (Join-Path $tools 'release\build_android.ps1') `
      -ScriptArgs $scriptArgs
  }
  'package-windows' {
    $scriptArgs = @($Rest | Where-Object { $_ })
    if ($scriptArgs -notcontains '-SkipPubGet') {
      $scriptArgs += '-SkipPubGet'
    }
    Invoke-ProjectScript `
      -Path (Join-Path $tools 'release\build_windows.ps1') `
      -ScriptArgs $scriptArgs
  }
  'install-build-android' {
    Install-AndroidApks -Source build -DryRun:($Rest -contains '-DryRun')
  }
  'install-package-android' {
    Install-AndroidApks -Source package -DryRun:($Rest -contains '-DryRun')
  }
  'logcat' {
    if (!$adb) {
      Write-Output '找不到 adb；检查 C:\dev\android-sdk\platform-tools\adb.exe'
      $script:ExitCode = 1
      break
    }
    & $adb logcat -d -t 500 2>&1 |
      Select-String -Pattern 'flutter|DioException|FormatException|Lanzou|SocketException|FATAL' |
      Select-Object -Last 30 | ForEach-Object { $_.Line }
    Write-Output "---- exit=$LASTEXITCODE"
  }
  'help' {
    Show-Help
  }
  { $_ -in @('gen', 'pubget', 'build-apk', 'install', 'install-android') } {
    Write-Output '动词已重命名：gen→gen-l10n，pubget→pub-get，build-apk→build-android；install/install-android→install-build-android 或 install-package-android'
    $script:ExitCode = 1
  }
  default {
    # 透传：devices / doctor / emulators / run 等（这些会弹一次批准）
    Invoke-Flutter -FlutterArgs (@($Verb) + @($Rest | Where-Object { $_ })) -Tail 20
  }
}

exit $script:ExitCode
