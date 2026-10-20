#requires -Version 5.1
Set-StrictMode -Version 2.0

# 发布脚本共用逻辑：版本号、Flutter/Android 工具定位、命令执行与 CI 输出。
# 这里的脚本同时兼容 Windows PowerShell 5.1、PowerShell 7 和 GitHub Actions 的
# Ubuntu / Windows runner。

function Test-WindowsHost {
  return ($env:OS -eq 'Windows_NT')
}

function Test-IsCI {
  return ($env:GITHUB_ACTIONS -eq 'true')
}

function Get-ProjectRoot {
  param([Parameter(Mandatory = $true)][string]$ScriptRoot)
  return (Resolve-Path -LiteralPath (Join-Path $ScriptRoot '../..')).Path
}

function Read-JavaProperties {
  param([Parameter(Mandatory = $true)][string]$Path)

  $properties = @{}
  if (!(Test-Path -LiteralPath $Path)) {
    return $properties
  }
  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('!')) {
      continue
    }
    $index = $trimmed.IndexOf('=')
    if ($index -lt 1) {
      $index = $trimmed.IndexOf(':')
    }
    if ($index -lt 1) {
      continue
    }
    $key = $trimmed.Substring(0, $index).Trim()
    $value = $trimmed.Substring($index + 1).Trim()
    $properties[$key] = $value
  }
  return $properties
}

function ConvertFrom-JavaPropertyPath {
  param([string]$Value)
  if (!$Value) {
    return $Value
  }
  return $Value.Replace('\\', '\')
}

function Get-VersionCode {
  param([Parameter(Mandatory = $true)][string]$Name)

  $release = [regex]::Match($Name, '^(\d{2})\.(\d+)\.(\d+)$')
  if ($release.Success) {
    return [int]$release.Groups[1].Value * 10000000 +
           [int]$release.Groups[2].Value * 100000 +
           [int]$release.Groups[3].Value * 10000 +
           9 * 100 + 99
  }

  $pre = [regex]::Match(
    $Name, '^(\d{2})\.(\d+)\.(\d+)-(snapshot|pre|beta|rc)\.(\d+)$')
  if (!$pre.Success) {
    return $null
  }
  $sequence = [int]$pre.Groups[5].Value
  if ($sequence -gt 99) {
    return $null
  }
  $stage = switch ($pre.Groups[4].Value) {
    'snapshot' { 1 }
    'pre' { 2 }
    'beta' { 2 }
    'rc' { 3 }
  }
  return [int]$pre.Groups[1].Value * 10000000 +
         [int]$pre.Groups[2].Value * 100000 +
         [int]$pre.Groups[3].Value * 10000 +
         $stage * 100 +
         $sequence
}

function Get-ReleaseVersion {
  param([Parameter(Mandatory = $true)][string]$Root)

  $pubspecPath = Join-Path $Root 'pubspec.yaml'
  if (!(Test-Path -LiteralPath $pubspecPath)) {
    throw "找不到 pubspec.yaml：$pubspecPath"
  }

  $versionLine = Get-Content -LiteralPath $pubspecPath |
    Where-Object { $_ -match '^version:\s*' } |
    Select-Object -First 1
  if (!$versionLine) {
    throw 'pubspec.yaml 里找不到 version:'
  }

  $versionRaw = ($versionLine -replace '^version:\s*', '').Trim()
  $match = [regex]::Match($versionRaw, '^([^+\s]+)\+(\d+)$')
  if (!$match.Success) {
    throw "pubspec.yaml 的 version 需要写成 版本号+versionCode，当前是 $versionRaw"
  }

  $name = $match.Groups[1].Value
  $code = [int]$match.Groups[2].Value
  $expectedCode = Get-VersionCode -Name $name
  if ($null -eq $expectedCode) {
    throw "版本号不符合规范（见 docs/VERSIONING.md）：$name"
  }
  if ($code -ne $expectedCode) {
    throw "versionCode 与公式不一致：应为 $expectedCode，pubspec 写的是 $code"
  }

  return [pscustomobject]@{
    Name = $name
    Code = $code
    ExpectedCode = $expectedCode
    IsPrerelease = $name.Contains('-')
    Tag = "v$name"
    Raw = $versionRaw
  }
}

function Assert-AppInfoVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)]$Version
  )

  $infoPath = Join-Path $Root 'lib/core/app_info.dart'
  if (!(Test-Path -LiteralPath $infoPath)) {
    throw "找不到 $infoPath"
  }
  $text = Get-Content -Raw -LiteralPath $infoPath

  $versionMatch = [regex]::Match($text, "const String appVersion = '([^']+)';")
  $buildMatch = [regex]::Match($text, 'const int appBuild = (\d+);')
  if (!$versionMatch.Success -or !$buildMatch.Success) {
    throw '无法从 lib/core/app_info.dart 读取 appVersion / appBuild'
  }
  if ($versionMatch.Groups[1].Value -ne $Version.Name) {
    throw "app_info.dart 的 appVersion 是 $($versionMatch.Groups[1].Value)，pubspec 是 $($Version.Name)"
  }
  if ([int]$buildMatch.Groups[1].Value -ne $Version.Code) {
    throw "app_info.dart 的 appBuild 是 $($buildMatch.Groups[1].Value)，pubspec 是 $($Version.Code)"
  }
}

function Get-GitCommit {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$Ref = 'HEAD'
  )

  $output = @(Invoke-ReleaseTool -Exe 'git' `
    -Arguments @('-C', $Root, 'rev-parse', $Ref) -Capture -Quiet)
  if ($output.Count -eq 0) {
    throw "无法解析 git 提交：$Ref"
  }
  return ($output | Select-Object -First 1).Trim()
}

function Find-Executable {
  param([Parameter(Mandatory = $true)][string[]]$Names)

  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
      return $command.Source
    }
  }
  return $null
}

function Get-FlutterCommand {
  param([Parameter(Mandatory = $true)][string]$Root)

  $localProperties = Join-Path (Join-Path $Root 'android') 'local.properties'
  $properties = Read-JavaProperties -Path $localProperties
  if ($properties.ContainsKey('flutter.sdk')) {
    $sdk = ConvertFrom-JavaPropertyPath $properties['flutter.sdk']
    $names = if (Test-WindowsHost) { @('flutter.bat', 'flutter') } else { @('flutter') }
    foreach ($name in $names) {
      $candidate = Join-Path (Join-Path $sdk 'bin') $name
      if (Test-Path -LiteralPath $candidate) {
        return $candidate
      }
    }
  }

  $names = if (Test-WindowsHost) { @('flutter.bat', 'flutter') } else { @('flutter') }
  $flutter = Find-Executable -Names $names
  if (!$flutter) {
    throw '找不到 flutter 命令'
  }
  return $flutter
}

function Get-DartCommand {
  param([Parameter(Mandatory = $true)][string]$Root)

  $flutter = Get-FlutterCommand -Root $Root
  $binDir = Split-Path -Parent $flutter
  $names = if (Test-WindowsHost) { @('dart.bat', 'dart') } else { @('dart') }
  foreach ($name in $names) {
    $candidate = Join-Path $binDir $name
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }
  $dart = Find-Executable -Names $names
  if (!$dart) {
    throw '找不到 dart 命令'
  }
  return $dart
}

function Get-AndroidSdk {
  param([Parameter(Mandatory = $true)][string]$Root)

  $candidates = @()
  $localProperties = Join-Path (Join-Path $Root 'android') 'local.properties'
  $properties = Read-JavaProperties -Path $localProperties
  if ($properties.ContainsKey('sdk.dir')) {
    $candidates += ConvertFrom-JavaPropertyPath $properties['sdk.dir']
  }
  $candidates += @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  throw '找不到 Android SDK，请设置 ANDROID_HOME 或 android/local.properties 的 sdk.dir'
}

function Get-ApkSigner {
  param([Parameter(Mandatory = $true)][string]$AndroidSdk)

  $buildToolsRoot = Join-Path $AndroidSdk 'build-tools'
  if (!(Test-Path -LiteralPath $buildToolsRoot)) {
    throw "找不到 build-tools：$buildToolsRoot"
  }
  $directories = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Where-Object { $_.Name -match '^\d+(\.\d+)+' } |
    Sort-Object { [version]($_.Name -replace '[^0-9.].*$', '') } -Descending

  foreach ($directory in $directories) {
    $names = if (Test-WindowsHost) { @('apksigner.bat', 'apksigner') } else { @('apksigner') }
    foreach ($name in $names) {
      $candidate = Join-Path $directory.FullName $name
      if (Test-Path -LiteralPath $candidate) {
        return $candidate
      }
    }
  }
  throw '找不到 apksigner，请检查 Android SDK build-tools'
}

function Invoke-ReleaseTool {
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [switch]$Capture,
    [switch]$Quiet,
    [int]$Tail = 40,
    [switch]$DryRun
  )

  if ($DryRun) {
    Write-Host ("[dry-run] {0} {1}" -f $Exe, ($Arguments -join ' ')) -ForegroundColor DarkGray
    return @()
  }

  # flutter / gradle 会把进度与镜像提示写到 stderr。Stop 模式下 PowerShell 会
  # 把这些内容当成终止错误，这里只按退出码判断成败。逐行写 Host 是为了让 CI
  # 日志在长时间构建时也能实时看到进度。
  $output = New-Object System.Collections.Generic.List[string]
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & $Exe @Arguments 2>&1 | ForEach-Object {
      $text = $_.ToString()
      $output.Add($text)
      if (!$Quiet) {
        Write-Host $text
      }
    }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }

  if ($exitCode -ne 0) {
    $output | Select-Object -Last $Tail | ForEach-Object { Write-Host $_ }
    throw "命令失败（exit $exitCode）：$Exe $($Arguments -join ' ')"
  }
  if ($Capture) {
    return $output.ToArray()
  }
}

function Get-RemoteTagCommit {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Tag
  )

  $lines = @(Invoke-ReleaseTool -Exe 'git' -Arguments @(
    '-C', $Root, 'ls-remote', 'origin',
    "refs/tags/$Tag", "refs/tags/$Tag^{}"
  ) -Capture -Quiet)
  if ($lines.Count -eq 0) {
    return $null
  }

  $tagSha = $null
  $peeledSha = $null
  foreach ($line in $lines) {
    $parts = ($line.ToString() -split '\s+', 2)
    if ($parts.Count -lt 2) {
      continue
    }
    if ($parts[1] -eq "refs/tags/$Tag") {
      $tagSha = $parts[0]
    } elseif ($parts[1] -eq "refs/tags/$Tag^{}") {
      $peeledSha = $parts[0]
    }
  }
  if ($peeledSha) {
    return $peeledSha
  }
  return $tagSha
}

function Set-CIOutput {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Value
  )
  if ($env:GITHUB_OUTPUT) {
    Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value "$Name=$Value" -Encoding utf8
  }
}

function Add-CISummary {
  param([Parameter(Mandatory = $true)][string]$Markdown)
  if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $Markdown -Encoding utf8
  }
}

function Format-BuildTime {
  # 统一注入带 Z 的 UTC 时间（GitHub Actions runner 是 UTC）；App 显示时
  # 转成本机时区。若这里直接输出 runner 本地时间，CI 包会少 8 小时。
  return [DateTime]::UtcNow.ToString(
    "yyyy-MM-dd'T'HH:mm:ss'Z'",
    [System.Globalization.CultureInfo]::InvariantCulture
  )
}

function Get-FileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-FingerprintFormat {
  param([Parameter(Mandatory = $true)][string]$Fingerprint)
  if ($Fingerprint -notmatch '^[0-9A-Fa-f]{64}$') {
    throw "签名指纹格式不对（应为 64 位十六进制）：$Fingerprint"
  }
}

Export-ModuleMember -Function @(
  'Test-WindowsHost',
  'Test-IsCI',
  'Get-ProjectRoot',
  'Read-JavaProperties',
  'ConvertFrom-JavaPropertyPath',
  'Get-VersionCode',
  'Get-ReleaseVersion',
  'Assert-AppInfoVersion',
  'Get-GitCommit',
  'Find-Executable',
  'Get-FlutterCommand',
  'Get-DartCommand',
  'Get-AndroidSdk',
  'Get-ApkSigner',
  'Invoke-ReleaseTool',
  'Get-RemoteTagCommit',
  'Set-CIOutput',
  'Add-CISummary',
  'Format-BuildTime',
  'Get-FileSha256',
  'Assert-FingerprintFormat'
)
