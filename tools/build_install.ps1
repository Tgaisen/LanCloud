# Build split APKs -> copy to outputs -> install to connected device -> launch app
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$pkg = 'com.lancloud.lancloud'
$activity = "$pkg/.MainActivity"
$adb = 'C:\dev\android-sdk\platform-tools\adb.exe'
$apkDir = Join-Path $root 'build\app\outputs\flutter-apk'
$outDir = Join-Path $root 'outputs'

# 版本名含预发布后缀（如 26.1.0-pre.3）；'+' 后面是 versionCode，不要
$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*([^+\s]+)\+').Matches[0].Groups[1].Value
Write-Output "==> Building LanCloud $version"
& (Join-Path $PSScriptRoot 'flutter.cmd') build apk --release --split-per-abi

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
# 产物命名：LanCloud_平台_版本_架构
$map = @{
    'app-arm64-v8a-release.apk'   = "LanCloud_android_${version}_arm64-v8a.apk"
    'app-armeabi-v7a-release.apk' = "LanCloud_android_${version}_armeabi-v7a.apk"
    'app-x86_64-release.apk'      = "LanCloud_android_${version}_x86_64.apk"
}
foreach ($key in $map.Keys) {
    Copy-Item (Join-Path $apkDir $key) (Join-Path $outDir $map[$key]) -Force
}
Write-Output '==> APKs copied to outputs/'

if (-not (Test-Path $adb)) {
    Write-Output '==> adb not found, skipping install'
    exit 0
}
$devices = (& $adb devices) | Select-String -Pattern "`tdevice$"
if (-not $devices) {
    Write-Output '==> No connected device, skipping install'
    exit 0
}

$abi = (& $adb shell getprop ro.product.cpu.abi).Trim()
$apkName = if ($abi -like 'arm64*') {
    "LanCloud_android_${version}_arm64-v8a.apk"
} elseif ($abi -like 'x86*') {
    "LanCloud_android_${version}_x86_64.apk"
} else {
    "LanCloud_android_${version}_armeabi-v7a.apk"
}
Write-Output "==> Installing $apkName to device ($abi)"
& $adb install -r (Join-Path $outDir $apkName)
& $adb shell am start -n $activity
Write-Output '==> Done'
