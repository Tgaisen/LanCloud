<#
.SYNOPSIS
  发布前校验：版本号、代码检查、Git 状态和 tag / Release 冲突。

.DESCRIPTION
  这是发布流程的第一段，只做检查，不构建、不修改仓库。

  - 解析 pubspec.yaml，按 docs/VERSIONING.md 校验 versionCode
  - 校验 lib/core/app_info.dart 与 pubspec.yaml 一致
  - 本地模式检查工作区干净、HEAD 已推送到 origin/main、tag 不存在
  - CI 模式检查 tag / Release 是否已经存在，并输出 should_release
  - 未跳过测试时执行 dart format / flutter analyze / flutter test

  CI 用法由 .github/workflows/release.yml 调用；本地通常由 tools/release.ps1
  调用。

.EXAMPLE
  pwsh -File tools/release/validate.ps1
.EXAMPLE
  pwsh -File tools/release/validate.ps1 -CI -ExpectedCertSha256 70BD...
#>
[CmdletBinding()]
param(
  # 在 GitHub Actions 中运行：跳过本地工作区检查，并计算 should_release
  [switch]$CI,
  # 跳过 dart format / flutter analyze / flutter test
  [switch]$SkipTests,
  # 跳过 flutter pub get（CI 已在前面执行过时可加）
  [switch]$SkipPubGet,
  # 只打印命令，不执行
  [switch]$DryRun,
  # 本地 dry-run 时允许工作区有未提交改动
  [switch]$AllowDirty,
  # 跳过远端 tag / release 检查（离线排查时使用）
  [switch]$SkipRemoteChecks,
  # 跳过 Android SDK / apksigner 检查（只发 Windows 时使用）
  [switch]$SkipAndroidTools,
  [string]$ExpectedCertSha256 =
    '70BD4AA85322FE26E67202FAC31729BDE1F854FA1BD2FD52C88FFCAA02EDB5BB'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'common.psm1') -Force

function Info([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Fail([string]$text) { throw $text }

$root = Get-ProjectRoot -ScriptRoot $PSScriptRoot
Set-Location $root
$isCI = $CI -or (Test-IsCI)
if ($isCI -and $env:GITHUB_REF -and $env:GITHUB_REF -ne 'refs/heads/main') {
  throw "Release 只能从 main 触发（当前 ref：$env:GITHUB_REF）"
}
$version = Get-ReleaseVersion -Root $root
Assert-AppInfoVersion -Root $root -Version $version
Assert-FingerprintFormat -Fingerprint $ExpectedCertSha256

Info "版本号 $($version.Name)（versionCode $($version.Code)，$(if ($version.IsPrerelease) { '预发布' } else { '正式版' })）"
Info "tag：$($version.Tag)"

$commit = if ($isCI -and $env:GITHUB_SHA) {
  $env:GITHUB_SHA
} else {
  Get-GitCommit -Root $root
}

if (!$isCI) {
  $branch = (& git -C $root branch --show-current).Trim()
  if ($branch -and $branch -ne 'main') {
    Fail "当前分支是 $branch，发布必须从 main 进行"
  }

  $dirty = & git -C $root status --porcelain
  if ($dirty -and !$AllowDirty) {
    Fail '工作区不干净，先把改动提交再发版'
  }
  if ($dirty) {
    if ($DryRun) {
      Write-Host '（dry-run）工作区有未提交改动，已跳过干净检查' -ForegroundColor DarkYellow
    } else {
      Write-Host '已允许工作区存在未提交改动（-AllowDirty）' -ForegroundColor DarkYellow
    }
  }

  if (!$SkipRemoteChecks) {
    $remoteLine = (& git -C $root ls-remote origin refs/heads/main) -join ''
    $remoteSha = ($remoteLine -split '\s+')[0]
    if ($commit -ne $remoteSha) {
      Fail '本地 HEAD 还没推送到 origin/main，先 git push'
    }
  }
  Info "git 状态正常（$($commit.Substring(0, 7))）"
} else {
  Info "CI 提交：$commit"
}

$shouldRelease = $true
$reason = '版本尚未发布'
$existingRelease = $null
$gh = $null

if (!$SkipRemoteChecks) {
  $gh = Find-Executable -Names @('gh', 'gh.exe')
  if (!$gh) {
    Fail '找不到 gh，请先安装 GitHub CLI'
  }
  if (!$isCI) {
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
  }

  $remoteTagCommit = Get-RemoteTagCommit -Root $root -Tag $version.Tag
  if ($remoteTagCommit) {
    if ($isCI) {
      if ($remoteTagCommit -ne $commit) {
        $shouldRelease = $false
        $reason = "tag $($version.Tag) 已指向 $($remoteTagCommit.Substring(0, 7))，不是本次提交"
      } else {
        # tag 已存在但 Release 可能只建到一半；草稿或无 Release 时允许重跑补齐。
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
          $releaseRaw = & $gh release view $version.Tag --json isDraft,url 2>$null
          $releaseExit = $LASTEXITCODE
        } finally {
          $ErrorActionPreference = $previous
        }
        if ($releaseExit -eq 0) {
          $existingRelease = ($releaseRaw -join "`n") | ConvertFrom-Json
          if ($existingRelease.isDraft) {
            $reason = '已有同名草稿 Release，将重新构建并补齐产物'
          } else {
            $shouldRelease = $false
            $reason = '该版本已经发布'
          }
        } else {
          $reason = 'tag 已存在但没有 Release，将补齐发布'
        }
      }
    } else {
      Fail "远端已存在 tag $($version.Tag)（$($remoteTagCommit.Substring(0, 7))）"
    }
  }
} else {
  $reason = '已跳过远端检查'
}

Set-CIOutput -Name 'version' -Value $version.Name
Set-CIOutput -Name 'version_code' -Value $version.Code.ToString()
Set-CIOutput -Name 'tag' -Value $version.Tag
Set-CIOutput -Name 'is_prerelease' -Value $(if ($version.IsPrerelease) { 'true' } else { 'false' })
Set-CIOutput -Name 'commit' -Value $commit
Set-CIOutput -Name 'should_release' -Value $(if ($shouldRelease) { 'true' } else { 'false' })
Set-CIOutput -Name 'reason' -Value $reason

Info $reason
Add-CISummary @"
### Release 校验

| 项目 | 值 |
| --- | --- |
| 版本 | ``$($version.Name)`` |
| versionCode | ``$($version.Code)`` |
| tag | ``$($version.Tag)`` |
| 提交 | ``$commit`` |
| 是否发布 | ``$(if ($shouldRelease) { '是' } else { '否' })`` |
| 原因 | $reason |
"@

if (!$shouldRelease) {
  Info '该版本不需要重新发布，后续构建与上传将跳过'
  return
}

# ---------------------------------------------------------------- 本地工具检查
if (!$isCI) {
  $null = Get-FlutterCommand -Root $root
  $null = Get-DartCommand -Root $root
  if (!$SkipAndroidTools) {
    $androidSdk = Get-AndroidSdk -Root $root
    $null = Get-ApkSigner -AndroidSdk $androidSdk
  }
}

# ---------------------------------------------------------------- 检查与测试
if (!$SkipTests) {
  $flutter = Get-FlutterCommand -Root $root
  $dart = Get-DartCommand -Root $root

  if (!$SkipPubGet) {
    Info 'flutter pub get'
    Invoke-ReleaseTool -Exe $flutter -Arguments @('pub', 'get') -DryRun:$DryRun
  }

  Info 'dart format 检查'
  Invoke-ReleaseTool -Exe $dart -Arguments @(
    'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool'
  ) -DryRun:$DryRun
  Info 'flutter analyze'
  Invoke-ReleaseTool -Exe $flutter -Arguments @('analyze') -DryRun:$DryRun
  Info 'flutter test'
  Invoke-ReleaseTool -Exe $flutter -Arguments @('test') -DryRun:$DryRun
}

Info '校验完成'
