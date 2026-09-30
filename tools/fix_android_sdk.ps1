$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sdkRoot = 'C:\dev\android-sdk'
$wanted = @('platforms;android-34')
$tmp = Join-Path $env:TEMP ('sdkfix_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

Write-Output 'Fetching repository index...'
$xmlPath = Join-Path $tmp 'repo.xml'
curl.exe -sS -L --retry 6 --retry-delay 5 -o $xmlPath 'https://dl.google.com/android/repository/repository2-3.xml'
if ($LASTEXITCODE -ne 0) { throw 'failed to download repository2-3.xml' }

[xml]$doc = Get-Content -Raw -Path $xmlPath
$urls = @{}
foreach ($node in $doc.SelectNodes("//*[local-name()='remotePackage']")) {
    $path = $node.GetAttribute('path')
    foreach ($arch in $node.SelectNodes("./*[local-name()='archives']/*[local-name()='archive']")) {
        $osNode = $arch.SelectSingleNode("./*[local-name()='host-os']")
        $osText = if ($osNode) { $osNode.InnerText } else { 'windows' }
        if ($osText -ne 'windows') { continue }
        $u = $arch.SelectSingleNode("./*[local-name()='complete']/*[local-name()='url']")
        if ($u -and -not $urls.ContainsKey($path)) {
            $urls[$path] = 'https://dl.google.com/android/repository/' + $u.InnerText
        }
    }
}

foreach ($p in $wanted) {
    if (-not $urls.ContainsKey($p)) { throw "no download url for $p" }
    $ver = $p.Split(';')[1]
    $dest = Join-Path $sdkRoot ("platforms\" + $ver)
    if (Test-Path $dest) { Write-Output "already installed: $p"; continue }
    $zip = Join-Path $tmp ($p.Replace(';', '_') + '.zip')
    Write-Output "Downloading $p ..."
    curl.exe -sS -L --retry 8 --retry-delay 5 --connect-timeout 30 -o $zip $urls[$p]
    if ($LASTEXITCODE -ne 0) { throw "download failed for $p" }
    $extract = Join-Path $tmp ($p.Replace(';', '_'))
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    tar.exe -xf $zip -C $extract
    if ($LASTEXITCODE -ne 0) { Expand-Archive -Path $zip -DestinationPath $extract }
    $top = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $top) { throw "unexpected layout for $p" }
    New-Item -ItemType Directory -Force -Path (Join-Path $sdkRoot 'platforms') | Out-Null
    Move-Item -LiteralPath $top.FullName -Destination $dest
    Write-Output "installed $p -> $dest"
}

$licDir = Join-Path $sdkRoot 'licenses'
New-Item -ItemType Directory -Force -Path $licDir | Out-Null
$sdkLicense = @(
    '8933bad161af4178b1185d1a37fbf41ea5269c55',
    'd56f5187479451eabf01fb78af6dfcb131a6481e',
    '24333f8a63b6825ea9c5514f83c2829b004d1fee'
)
Set-Content -LiteralPath (Join-Path $licDir 'android-sdk-license') -Value $sdkLicense
Set-Content -LiteralPath (Join-Path $licDir 'android-sdk-preview-license') -Value '84831b9409646a918e30573bab4c9c91346d8abd'

Remove-Item -LiteralPath $tmp -Recurse -Force
Write-Output 'SDK_FIX_DONE'
