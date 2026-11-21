#requires -Version 5.1
Set-StrictMode -Version 2.0

# LanCloud 本地开发工具链的唯一路径来源。
#
# Agent、发布脚本和 flutter.cmd 都从这里取得 Flutter / Dart / JDK / Android SDK，
# 避免不同入口选中 Android Studio 自带 JDK 或其他 Flutter SDK。

function Get-LanCloudToolchain {
  $windowsHost = $env:OS -eq 'Windows_NT'

  if ($windowsHost) {
    $flutterSdk = 'C:\dev\flutter'
    $javaRoot = 'C:\dev\java17'
    $androidSdk = 'C:\dev\android-sdk'

    if (Test-Path -LiteralPath $flutterSdk) {
      $flutter = Join-Path $flutterSdk 'bin\flutter.bat'
      $dart = Join-Path $flutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
    } else {
      $flutterCommand = Get-Command flutter.bat, flutter -ErrorAction SilentlyContinue |
        Select-Object -First 1
      if (!$flutterCommand) {
        throw '找不到 Flutter SDK；预期路径是 C:\dev\flutter'
      }
      $flutter = $flutterCommand.Source
      $flutterBin = Split-Path -Parent $flutter
      $flutterSdk = Split-Path -Parent $flutterBin
      $dart = Join-Path $flutterSdk 'bin\cache\dart-sdk\bin\dart.exe'
    }

    if (!(Test-Path -LiteralPath $flutter)) {
      throw "找不到 Flutter：$flutter"
    }

    $javaHome = $null
    if (Test-Path -LiteralPath $javaRoot) {
      $javaDirectory = Get-ChildItem -LiteralPath $javaRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1
      if ($javaDirectory) {
        $javaHome = $javaDirectory.FullName
      }
    }
    if (!$javaHome) {
      throw '找不到 JDK 17；预期路径是 C:\dev\java17 下的 JDK 目录'
    }

    $adb = Join-Path $androidSdk 'platform-tools\adb.exe'
    if (!(Test-Path -LiteralPath $adb)) {
      $adb = $null
    }
  } else {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if (!$flutterCommand) {
      throw '找不到 flutter 命令'
    }
    $flutter = $flutterCommand.Source
    $flutterSdk = Split-Path -Parent (Split-Path -Parent $flutter)
    $dartCommand = Get-Command dart -ErrorAction SilentlyContinue |
      Select-Object -First 1
    $dart = if ($dartCommand) { $dartCommand.Source } else { $null }
    $androidSdk = $env:ANDROID_HOME
    if (!$androidSdk) {
      $androidSdk = $env:ANDROID_SDK_ROOT
    }
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue |
      Select-Object -First 1
    $adb = if ($adbCommand) { $adbCommand.Source } else { $null }
    $javaHome = $env:JAVA_HOME
  }

  if ($dart -and (Test-Path -LiteralPath $dart)) {
    $dartBin = Split-Path -Parent $dart
  } else {
    $dartBin = $null
  }
  $flutterBin = Split-Path -Parent $flutter

  $env:JAVA_HOME = $javaHome
  if ($androidSdk -and (Test-Path -LiteralPath $androidSdk)) {
    $env:ANDROID_HOME = $androidSdk
  }
  $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.googleapis.com'
  $env:PUB_HOSTED_URL = 'https://pub.dev'

  $pathParts = @($flutterBin)
  if ($javaHome) {
    $pathParts += (Join-Path $javaHome 'bin')
  }
  if ($dartBin) {
    $pathParts += $dartBin
  }
  $env:Path = (@($pathParts) -join ';') + ';' + $env:Path

  return [pscustomobject]@{
    Flutter = $flutter
    Dart = $dart
    Adb = $adb
    FlutterSdk = $flutterSdk
    AndroidSdk = $androidSdk
    JavaHome = $javaHome
  }
}

Export-ModuleMember -Function Get-LanCloudToolchain
