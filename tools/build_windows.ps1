<#
.SYNOPSIS
  兼容入口：Windows 构建已拆分到 tools/release/build_windows.ps1。

.DESCRIPTION
  保留这个路径是为了不破坏 README 与已有本地脚本；参数会原样转发。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1 -SkipTests -SkipZip
#>
[CmdletBinding()]
param(
  [switch]$SkipTests,
  [switch]$SkipPubGet,
  [switch]$SkipZip,
  [switch]$CI,
  [switch]$DryRun,
  [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'
$releaseScript = Join-Path (Join-Path $PSScriptRoot 'release') 'build_windows.ps1'
if (!(Test-Path -LiteralPath $releaseScript)) {
  throw "找不到构建脚本：$releaseScript"
}

& $releaseScript @PSBoundParameters
