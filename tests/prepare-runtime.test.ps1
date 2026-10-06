$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('GamesCoverflow-runtime-' + [guid]::NewGuid().ToString('N'))
try {
    & (Join-Path $root 'Prepare-WebRuntime.ps1') -Destination $fixture
    $library = Get-Content -LiteralPath (Join-Path $fixture 'library.json') -Raw | ConvertFrom-Json
    if (@($library.games).Count -ne 0) { throw 'Starter library must be empty.' }
    if ((Get-Content -LiteralPath (Join-Path $fixture 'game-details.json') -Raw).Trim() -ne '{}') { throw 'Starter details must be empty.' }
    [IO.File]::WriteAllText((Join-Path $fixture 'library.json'), '{"games":[{"id":"synthetic"}]}')
    [IO.File]::WriteAllText((Join-Path $fixture 'game-details.json'), '{"synthetic":{"synopsis":"local"}}')
    & (Join-Path $root 'Prepare-WebRuntime.ps1') -Destination $fixture
    $library = Get-Content -LiteralPath (Join-Path $fixture 'library.json') -Raw | ConvertFrom-Json
    if ($library.games[0].id -ne 'synthetic') { throw 'Preparation replaced existing library.' }
    $details = Get-Content -LiteralPath (Join-Path $fixture 'game-details.json') -Raw | ConvertFrom-Json
    if ($details.synthetic.synopsis -ne 'local') { throw 'Preparation replaced existing details.' }
    foreach ($name in @('index.html','style.css','app.js')) {
        if (-not (Test-Path -LiteralPath (Join-Path $fixture $name))) { throw "Missing static file: $name" }
    }
    Write-Output 'PASS: install web preparation starts empty and preserves existing private data.'
} finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolved = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notmatch '^GamesCoverflow-runtime-[0-9a-f]{32}$') { throw 'Unsafe fixture cleanup path.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
