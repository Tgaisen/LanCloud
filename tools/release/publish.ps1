<#
.SYNOPSIS
  创建/补齐 GitHub Release，并上传 Android APK 与 Windows 便携版。

.DESCRIPTION
  这是发布流程的最后一段：

  - 按版本号定位 tag（v<版本>）
  - tag 不存在时创建带注释的 tag 并推送
  - 默认创建 draft Release（可用 -Draft:$false 直接发布）
  - 已发布版本直接跳过；同名草稿则重新上传产物（可重跑失败任务）
  - 上传后核对 3 个 APK 和 Windows zip 是否都已挂到 Release

  需要 GitHub CLI（gh）已登录；GitHub Actions 中使用 GITHUB_TOKEN。

.EXAMPLE
  pwsh -File tools/release/publish.ps1
.EXAMPLE
  pwsh -File tools/release/publish.ps1 -Draft:$false
.EXAMPLE
  pwsh -File tools/release/publish.ps1 -RequireWindows:$false
#>
[CmdletBinding()]
param(
  # 默认从 pubspec.yaml 读取版本；一般不需要手动指定
  [string]$Tag = '',
  # 默认使用 GITHUB_SHA 或当前 HEAD
  [string]$Commit = '',
  # 产物目录，默认 <repo>/outputs
  [string]$AssetsDir = '',
  # 手动指定产物列表（不传则按版本号在 AssetsDir 中查找）
  [string[]]$Assets = @(),
  # 发布说明；不传时优先找 docs/releases/<版本>.md，再回退到自动生成
  [string]$NotesFile = '',
  # 默认创建 draft；本地想直接发布时传 -Draft:$false
  [bool]$Draft = $true,
  # 是否要求 Windows zip 存在
  [bool]$RequireWindows = $true,
  # 是否要求三个 Android APK 存在
  [bool]$RequireAndroid = $true,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1') -Force

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Fail([string]$text) { throw $text }

$root = Get-ProjectRoot -ScriptRoot $PSScriptRoot
Set-Location $root
$version = Get-ReleaseVersion -Root $root
if (!$Tag) {
  $Tag = $version.Tag
}
if ($Tag -ne $version.Tag) {
  Fail "tag 与版本号不一致：版本是 $($version.Tag)，传入的是 $Tag"
}
if (!$Commit) {
  $Commit = if ($env:GITHUB_SHA) {
    $env:GITHUB_SHA
  } else {
    Get-GitCommit -Root $root
  }
}

$gh = Find-Executable -Names @('gh', 'gh.exe')
if (!$gh) {
  Fail '找不到 gh，请先安装 GitHub CLI（winget install GitHub.cli）'
}
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $gh auth status 2>&1 | Out-Null
  $authExit = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previous
}
if ($authExit -ne 0) {
  Fail "gh 还没登录，先执行：`n  & '$gh' auth login"
}

# ---------------------------------------------------------------- 产物
if (!$AssetsDir) {
  $AssetsDir = Join-Path $root 'outputs'
}
if ($Assets.Count -eq 0) {
  $names = @()
  if ($RequireAndroid) {
    $names += @(
      "LanCloud_android_$($version.Name)_arm64-v8a.apk",
      "LanCloud_android_$($version.Name)_armeabi-v7a.apk",
      "LanCloud_android_$($version.Name)_x86_64.apk"
    )
  }
  if ($RequireWindows) {
    $names += "LanCloud_windows_$($version.Name)_x64_portable.zip"
  }
  foreach ($name in $names) {
    $Assets += (Join-Path $AssetsDir $name)
  }
}

if ($Assets.Count -eq 0) {
  Fail '没有可上传的产物'
}
if (!$DryRun) {
  foreach ($asset in $Assets) {
    if (!(Test-Path -LiteralPath $asset)) {
      Fail "产物缺失：$asset"
    }
  }
}

Info "发布版本 $($version.Name)（tag $Tag）"
Info "产物：$($Assets.Count) 个"

# ---------------------------------------------------------------- Release 状态
function Get-ExistingRelease {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = & $gh release view $Tag --json isDraft,url 2>$null
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($code -ne 0) {
    return $null
  }
  return ($raw -join "`n") | ConvertFrom-Json
}

$existingRelease = Get-ExistingRelease
if ($existingRelease -and !$existingRelease.isDraft) {
  Info "Release 已发布：$($existingRelease.url)"
  Add-CISummary "### Release 已存在`n`n版本 ``$($version.Name)`` 已经发布，本次跳过上传。"
  return
}

# ---------------------------------------------------------------- tag
$remoteTagCommit = Get-RemoteTagCommit -Root $root -Tag $Tag
if ($remoteTagCommit) {
  if ($remoteTagCommit -ne $Commit) {
    Fail "远端 tag $Tag 指向 $remoteTagCommit，不是本次提交 $Commit"
  }
  Info "远端 tag 已存在（$($remoteTagCommit.Substring(0, 7))）"
} else {
  Info "创建并推送 tag：$Tag"
  $localTag = (@(Invoke-ReleaseTool -Exe 'git' `
    -Arguments @('-C', $root, 'tag', '-l', $Tag) -Capture -Quiet) -join '').Trim()
  if ($localTag) {
    $localTagCommit = (@(Invoke-ReleaseTool -Exe 'git' `
      -Arguments @('-C', $root, 'rev-list', '-n', '1', $Tag) -Capture -Quiet) -join '').Trim()
    if ($localTagCommit -ne $Commit) {
      Fail "本地 tag $Tag 指向 $localTagCommit，不是本次提交 $Commit"
    }
    Info "本地 tag 已存在（$($localTagCommit.Substring(0, 7))），直接推送"
  } else {
    $configArgs = @()
    if (Test-IsCI) {
      $configArgs = @(
        '-c', 'user.name=github-actions[bot]',
        '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com'
      )
    }
    Invoke-ReleaseTool -Exe 'git' -Arguments (@(
      '-C', $root
    ) + $configArgs + @(
      'tag', '-a', $Tag, $Commit, '-m', $version.Name
    )) -DryRun:$DryRun
  }
  Invoke-ReleaseTool -Exe 'git' -Arguments @(
    '-C', $root, 'push', 'origin', $Tag
  ) -DryRun:$DryRun
}

# ---------------------------------------------------------------- 创建 / 补齐
$prereleaseArgs = @()
if ($version.IsPrerelease) {
  $prereleaseArgs = @('--prerelease', '--latest=false')
}

if ($existingRelease) {
  Info "补齐已有草稿 Release：$Tag"
  Invoke-ReleaseTool -Exe $gh -Arguments (@(
    'release', 'upload', $Tag
  ) + $Assets + @('--clobber')) -DryRun:$DryRun

  $editArgs = @(
    'release', 'edit', $Tag,
    '--title', $version.Name
  ) + $prereleaseArgs
  if ($Draft) {
    $editArgs += '--draft'
  } else {
    $editArgs += '--draft=false'
  }
  if ($NotesFile) {
    $notesPath = if ([IO.Path]::IsPathRooted($NotesFile)) {
      $NotesFile
    } else {
      Join-Path $root $NotesFile
    }
    if (!(Test-Path -LiteralPath $notesPath)) {
      Fail "找不到发布说明文件：$notesPath"
    }
    $editArgs += @('--notes-file', $notesPath)
  }
  Invoke-ReleaseTool -Exe $gh -Arguments $editArgs -DryRun:$DryRun
} else {
  Info "创建 Release：$Tag"
  if (!$NotesFile) {
    $candidate = Join-Path (Join-Path $root 'docs/releases') "$($version.Name).md"
    if (Test-Path -LiteralPath $candidate) {
      $NotesFile = $candidate
    }
  }

  $createArgs = @(
    'release', 'create', $Tag,
    '--verify-tag',
    '--title', $version.Name
  )
  if ($Draft) {
    $createArgs += '--draft'
  }
  $createArgs += $prereleaseArgs
  if ($NotesFile) {
    $notesPath = if ([IO.Path]::IsPathRooted($NotesFile)) {
      $NotesFile
    } else {
      Join-Path $root $NotesFile
    }
    if (!(Test-Path -LiteralPath $notesPath)) {
      Fail "找不到发布说明文件：$notesPath"
    }
    $createArgs += @('--notes-file', $notesPath)
  } else {
    $createArgs += '--generate-notes'
  }
  $createArgs += $Assets
  Invoke-ReleaseTool -Exe $gh -Arguments $createArgs -DryRun:$DryRun
}

if ($DryRun) {
  Info 'dry-run 结束：未创建 tag、未创建 Release'
  return
}

# ---------------------------------------------------------------- 核对
$releaseInfo = (& $gh release view $Tag --json isDraft,url,assets 2>$null) -join "`n"
if ($LASTEXITCODE -ne 0) {
  Fail "无法读取 Release：$Tag"
}
$release = $releaseInfo | ConvertFrom-Json
$uploadedNames = @($release.assets | ForEach-Object { $_.name })
foreach ($asset in $Assets) {
  $name = Split-Path -Leaf $asset
  if ($uploadedNames -notcontains $name) {
    Fail "Release 中缺少产物：$name"
  }
}

$draftText = if ($release.isDraft) { 'draft' } else { '已发布' }
Info "Release $draftText：$($release.url)"
Add-CISummary @"
### GitHub Release

- 版本：$($version.Name)
- tag：$Tag
- 状态：$draftText
- 地址：$($release.url)
- 产物：$($Assets.Count) 个
"@
