<#
.SYNOPSIS
  下载并校验固定版本的 NuGet CLI。

.DESCRIPTION
  用于 Windows CI。下载后先校验 SHA-256，匹配时才加入 GITHUB_PATH。
  在本地运行时只下载到临时目录并输出路径，不修改系统 PATH。
#>
[CmdletBinding()]
param(
  [string]$Version = '7.9.0',
  [string]$ExpectedSha256 =
    '992D70CAC5B06C38EFEC91806CABA64CDCC07E6D963A0959DBBBAF264D33B800'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$tempRoot = if ($env:RUNNER_TEMP) {
  $env:RUNNER_TEMP
} else {
  [IO.Path]::GetTempPath()
}
$nugetDir = Join-Path $tempRoot "nuget-$Version"
$nugetPath = Join-Path $nugetDir 'nuget.exe'

New-Item -ItemType Directory -Force -Path $nugetDir | Out-Null
Invoke-WebRequest `
  -Uri "https://dist.nuget.org/win-x86-commandline/v$Version/nuget.exe" `
  -OutFile $nugetPath

$actual = (Get-FileHash -LiteralPath $nugetPath -Algorithm SHA256).Hash
if ($actual -ne $ExpectedSha256) {
  throw "NuGet SHA-256 不匹配：$actual"
}

if ($env:GITHUB_PATH) {
  Add-Content -Path $env:GITHUB_PATH -Value $nugetDir
}
Write-Host "NuGet $Version 已校验：$nugetPath"
