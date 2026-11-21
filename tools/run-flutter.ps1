# flutter.cmd 的 PowerShell 启动器；参数由 ValueFromRemainingArguments 原样转发。
param(
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# Windows PowerShell 的 -File 参数绑定会把 `--debug` 识别成公共参数。
if ($PSBoundParameters.ContainsKey('Debug') -and $Rest -notcontains '--debug') {
  $Rest = @('--debug') + @($Rest)
}

Import-Module (Join-Path $PSScriptRoot 'toolchain.psm1') -Force
$toolchain = Get-LanCloudToolchain

$ErrorActionPreference = 'Continue'
& $toolchain.Flutter @Rest
exit $LASTEXITCODE
