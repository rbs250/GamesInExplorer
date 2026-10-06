$ErrorActionPreference = 'Stop'
$module = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('GamesCoverflow-artwork-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" } }
function Assert-SafeFixture([string]$target) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($target).TrimEnd('\')
    Assert ($resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolved) -match '^GamesCoverflow-artwork-[0-9a-f]{32}$') 'recursive cleanup must stay within its temporary fixture'
}
function New-Png([string]$path, [int]$width, [int]$height, [int]$argb) {
    $bitmap = New-Object Drawing.Bitmap($width, $height)
    try {
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.Clear([Drawing.Color]::FromArgb($argb)) } finally { $graphics.Dispose() }
        $bitmap.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}
try {
    Add-Type -AssemblyName System.Drawing
    $web = Join-Path $fixture 'web'
    $steam = Join-Path $fixture 'steam'
    $install = Join-Path $steam 'steamapps/common/Test Game'
    $cache = Join-Path $steam 'appcache/librarycache/100001'
    New-Item -ItemType Directory -Force -Path $web, (Join-Path $web 'covers'), $install, $cache, (Join-Path $fixture 'desktop') | Out-Null
    Copy-Item -LiteralPath (Join-Path $module 'Scan-Library.ps1') -Destination $fixture
    Copy-Item -LiteralPath (Join-Path $module 'Import-Cover.ps1') -Destination $fixture
    [IO.File]::WriteAllText((Join-Path $web 'launch.ini'), "[steam-100001]`r`ntarget=steam://rungameid/100001`r`n")
    [IO.File]::WriteAllText((Join-Path $steam 'steamapps/appmanifest_100001.acf'), '"appid" "100001" "name" "Test Game" "StateFlags" "4" "installdir" "Test Game"')
    [IO.File]::WriteAllText((Join-Path $web 'game-details.json'), '{"steam-100001":{"defaultCover":"covers/catalog.png"}}')
    New-Png (Join-Path $web 'covers/catalog.png') 12 12 ([Drawing.Color]::Blue.ToArgb())
    New-Png (Join-Path $cache 'library_600x900.png') 12 12 ([Drawing.Color]::Green.ToArgb())
    $source = Join-Path $fixture 'source.bmp'
    $large = New-Object Drawing.Bitmap(1800, 600)
    try { $large.Save($source, [Drawing.Imaging.ImageFormat]::Bmp) } finally { $large.Dispose() }
    & (Join-Path $fixture 'Import-Cover.ps1') -GameId 'steam-100001' -SourcePath $source
    $custom = Join-Path $fixture 'User Covers/steam-100001.png'
    Assert (Test-Path -LiteralPath $custom) 'valid image must be persisted outside web'
    $normalized = [Drawing.Image]::FromFile($custom)
    try { Assert ($normalized.Width -eq 1200 -and $normalized.Height -eq 400) 'large image must be normalized within 1200px while keeping aspect ratio' } finally { $normalized.Dispose() }
    $oldHash = (Get-FileHash -LiteralPath $custom -Algorithm SHA256).Hash
    [IO.File]::WriteAllText((Join-Path $fixture 'bad.jpg'), 'not an image')
    $rejected = $false
    try { & (Join-Path $fixture 'Import-Cover.ps1') -GameId 'steam-100001' -SourcePath (Join-Path $fixture 'bad.jpg') } catch { $rejected = $true }
    Assert $rejected 'malformed image must be rejected'
    Assert ((Get-FileHash -LiteralPath $custom -Algorithm SHA256).Hash -eq $oldHash) 'malformed image must preserve existing cover'
    $rejected = $false
    try { & (Join-Path $fixture 'Import-Cover.ps1') -GameId 'steam-999999' -SourcePath $source } catch { $rejected = $true }
    Assert $rejected 'unknown game ID must be rejected'
    Assert (-not (Test-Path -LiteralPath (Join-Path $fixture 'User Covers/steam-999999.png'))) 'unknown ID must not create a cover'
    & (Join-Path $fixture 'Scan-Library.ps1') -SteamPath $steam -Destination $web -ShortcutRoots @((Join-Path $fixture 'desktop')) | Out-Null
    $library = Get-Content -LiteralPath (Join-Path $web 'library.json') -Raw | ConvertFrom-Json
    Assert ($library.games[0].cover -match '^covers/steam-100001\.png\?v=\d+$') 'rescan must serve custom cover with cache buster'
    Assert ($library.games[0].customCover -eq $true) 'imported art must be marked as a custom cover'
    Assert ((Get-FileHash -LiteralPath (Join-Path $web 'covers/steam-100001.png') -Algorithm SHA256).Hash -eq $oldHash) 'custom cover must outrank Steam cache and catalog default'
    $launch = [IO.File]::ReadAllText((Join-Path $web 'launch.ini'))
    Assert ($launch.Contains('website=https://store.steampowered.com/app/100001/')) 'Steam source URL must use the fixed store endpoint'
    Remove-Item -LiteralPath $custom
    Remove-Item -LiteralPath (Join-Path $cache 'library_600x900.png')
    & (Join-Path $fixture 'Scan-Library.ps1') -SteamPath $steam -Destination $web -ShortcutRoots @((Join-Path $fixture 'desktop')) | Out-Null
    $library = Get-Content -LiteralPath (Join-Path $web 'library.json') -Raw | ConvertFrom-Json
    Assert ($library.games[0].cover -eq 'covers/catalog.png') 'safe catalog default should fill a missing cover'
    Assert ($library.games[0].customCover -eq $false) 'catalog default must not be marked as custom art'
    [IO.File]::WriteAllText((Join-Path $web 'game-details.json'), '{"steam-100001":{"defaultCover":"../source.bmp"}}')
    & (Join-Path $fixture 'Scan-Library.ps1') -SteamPath $steam -Destination $web -ShortcutRoots @((Join-Path $fixture 'desktop')) | Out-Null
    $library = Get-Content -LiteralPath (Join-Path $web 'library.json') -Raw | ConvertFrom-Json
    Assert ($library.games[0].cover -eq '') 'unsafe catalog path must be ignored'
    & (Join-Path $fixture 'Scan-Library.ps1') -SteamPath $steam -Destination $web -ShortcutRoots @((Join-Path $fixture 'desktop')) -ArtworkId 'steam-100001' -ArtworkSource $source | Out-Null
    $library = Get-Content -LiteralPath (Join-Path $web 'library.json') -Raw | ConvertFrom-Json
    Assert ($library.games[0].customCover -eq $true) 'scanner must import a native-selected source path without a second picker'
    Write-Output 'PASS: normalized import, rejection, cover precedence, catalog fallback, and source mapping.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Assert-SafeFixture $fixture; Remove-Item -LiteralPath $fixture -Recurse -Force }
}
