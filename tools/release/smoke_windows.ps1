<#
.SYNOPSIS
  启动 Windows release 产物并确认进程不会立即退出。

.DESCRIPTION
  用于 CI 和发布前冒烟，捕获运行库缺失、动态 DLL 缺失以及启动阶段崩溃。
  脚本会把标准输出和标准错误重定向到临时日志；进程提前退出时打印日志并失败。

.EXAMPLE
  pwsh -File tools/release/smoke_windows.ps1 `
    -Executable build/windows/x64/runner/Release/lancloud.exe
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Executable,
  [ValidateRange(1, 120)][int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'

$file = Get-Item -LiteralPath $Executable
$workingDir = Split-Path -Parent $file.FullName
$logRoot = if ($env:RUNNER_TEMP) {
  $env:RUNNER_TEMP
} else {
  [IO.Path]::GetTempPath()
}
$suffix = [Guid]::NewGuid().ToString('N')
$stdoutPath = Join-Path $logRoot "lancloud-smoke-$suffix.stdout.log"
$stderrPath = Join-Path $logRoot "lancloud-smoke-$suffix.stderr.log"

Write-Host "==> 启动 Windows 冒烟：$($file.FullName)"
$process = Start-Process `
  -FilePath $file.FullName `
  -WorkingDirectory $workingDir `
  -RedirectStandardOutput $stdoutPath `
  -RedirectStandardError $stderrPath `
  -PassThru
if (!$process) {
  throw "无法启动进程：$($file.FullName)"
}

try {
  Start-Sleep -Seconds $TimeoutSeconds
  $process.Refresh()
  if ($process.HasExited) {
    foreach ($logPath in @($stdoutPath, $stderrPath)) {
      if (Test-Path -LiteralPath $logPath) {
        $content = Get-Content -Raw -LiteralPath $logPath
        if ($content) {
          Write-Host "---- $(Split-Path -Leaf $logPath) ----"
          Write-Host $content
        }
      }
    }
    throw "Windows 进程在 $TimeoutSeconds 秒内退出，退出码 $($process.ExitCode)"
  }
  Write-Host "==> 进程存活 $TimeoutSeconds 秒，启动冒烟通过"
} finally {
  $process.Refresh()
  if (!$process.HasExited) {
    Stop-Process -Id $process.Id -Force
    $null = $process.WaitForExit(5000)
  }
}
