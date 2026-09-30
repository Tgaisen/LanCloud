$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sdkRoot = 'C:\dev\android-sdk'
$version = '28.2.13676358'
$dest = Join-Path $sdkRoot "ndk\$version"

if (Test-Path (Join-Path $dest 'source.properties')) {
    Write-Output "NDK $version already installed."
    exit 0
}

$tmp = Join-Path $env:TEMP ('ndk_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Output 'Fetching repository index...'
$xmlPath = Join-Path $tmp 'repo.xml'
curl.exe -sS -L --retry 6 --retry-delay 5 -o $xmlPath 'https://dl.google.com/android/repository/repository2-3.xml'
if ($LASTEXITCODE -ne 0) { throw 'failed to download repository2-3.xml' }

[xml]$doc = Get-Content -Raw -Path $xmlPath
$url = $null
foreach ($node in $doc.SelectNodes("//*[local-name()='remotePackage']")) {
    if ($node.GetAttribute('path') -ne "ndk;$version") { continue }
    foreach ($arch in $node.SelectNodes("./*[local-name()='archives']/*[local-name()='archive']")) {
        $osNode = $arch.SelectSingleNode("./*[local-name()='host-os']")
        if ($osNode -and $osNode.InnerText -ne 'windows') { continue }
        $u = $arch.SelectSingleNode("./*[local-name()='complete']/*[local-name()='url']")
        if ($u) { $url = 'https://dl.google.com/android/repository/' + $u.InnerText; break }
    }
    if ($url) { break }
}
if (-not $url) { throw "Could not find download url for ndk;$version" }
Write-Output "Downloading $url ..."

$zip = Join-Path $tmp 'ndk.zip'
curl.exe -sS -L --retry 8 --retry-delay 5 --connect-timeout 30 -o $zip $url
if ($LASTEXITCODE -ne 0) { throw 'NDK download failed' }

$extract = Join-Path $tmp 'x'
New-Item -ItemType Directory -Force -Path $extract | Out-Null
Write-Output 'Extracting...'
tar.exe -xf $zip -C $extract
if ($LASTEXITCODE -ne 0) { Expand-Archive -Path $zip -DestinationPath $extract }

$top = Get-ChildItem $extract -Directory | Select-Object -First 1
if (-not $top) { throw 'unexpected NDK archive layout' }
New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
Move-Item -LiteralPath $top.FullName -Destination $dest

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Output "NDK installed to $dest"
