$ErrorActionPreference = 'Stop'
$module = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('GamesCoverflow-owned-' + [guid]::NewGuid().ToString('N'))
function Assert([bool]$condition, [string]$message) { if (-not $condition) { throw "FAIL: $message" } }
function Assert-SafeTree([string]$target) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $root = [IO.Path]::GetFullPath($fixture).TrimEnd('\')
    $resolved = [IO.Path]::GetFullPath($target).TrimEnd('\')
    if (-not $root.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($root) -notmatch '^GamesCoverflow-owned-[0-9a-f]{32}$' -or
        ($resolved -ne $root -and -not $resolved.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase))) {
        throw "Unsafe recursive cleanup path: $target"
    }
}
function Scan([string]$source = '', [bool]$offline = $true, [string]$portraitBaseUrl = '') {
    $args = @{ SteamPath = (Join-Path $fixture 'steam'); Destination = (Join-Path $fixture 'web'); ShortcutRoots = @((Join-Path $fixture 'desktop')); SteamId = '76561198000000000'; Offline = $offline }
    if ($source) { $args.OwnedSourcePath = $source }
    if ($portraitBaseUrl) { $args.PortraitBaseUrl = $portraitBaseUrl }
    & (Join-Path $module 'Scan-Library.ps1') @args | Out-Null
    return Get-Content -LiteralPath (Join-Path $fixture 'web/library.json') -Raw | ConvertFrom-Json
}
try {
    $steam = Join-Path $fixture 'steam'
    $web = Join-Path $fixture 'web'
    $source = Join-Path $fixture 'owned-source.json'
    $manifest = Join-Path $steam 'steamapps/appmanifest_100001.acf'
    New-Item -ItemType Directory -Force -Path $web, (Join-Path $steam 'steamapps/common/Installed Game'), (Join-Path $fixture 'desktop') | Out-Null
    [IO.File]::WriteAllText($manifest, '"appid" "100001" "name" "Installed Game" "StateFlags" "4" "installdir" "Installed Game"')
    [IO.File]::WriteAllText($source, '{"steamId":"76561198000000000","complete":true,"games":[{"appid":100001,"name":"Installed Game","type":"game"},{"appid":200002,"name":"Owned Game","type":"game"},{"appid":300003,"name":"Extra DLC","type":"dlc"},{"appid":"bad-id","name":"Invalid Game","type":"game"}]}')

    $library = Scan $source
    Assert (@($library.games).Count -eq 2) 'overlap deduplicates and DLC/invalid IDs are omitted'
    $installed = @($library.games | Where-Object id -eq 'steam-100001')[0]
    $owned = @($library.games | Where-Object id -eq 'steam-200002')[0]
    Assert ($installed.installed -eq $true) 'installed overlap remains installed'
    Assert ($owned.installed -eq $false -and $owned.folder -eq '' -and $owned.sizeGB -eq 0) 'owned-only record has uninstall state'
    $launch = [IO.File]::ReadAllText((Join-Path $web 'launch.ini'))
    Assert ($launch.Contains('target=steam://install/200002')) 'owned-only action installs the selected app'
    Assert ($launch.Contains('target=steam://rungameid/100001')) 'installed action launches the selected app'
    Assert ($launch.Contains('website=https://store.steampowered.com/app/200002/')) 'owned-only source URL is the exact store app URL'
    Assert (Test-Path -LiteralPath (Join-Path $web 'owned-steam.json')) 'successful source refresh persists snapshot'

    [IO.File]::WriteAllText($source, '<html>Sign In</html>')
    $library = Scan $source
    Assert (@($library.games).Count -eq 2) 'failed source preserves the cached owned list'
    Remove-Item -LiteralPath $source
    $library = Scan
    Assert (@($library.games).Count -eq 2) 'offline scan uses cached ownership'

    Remove-Item -LiteralPath $manifest
    $installedFolder = Join-Path $steam 'steamapps/common/Installed Game'
    Assert-SafeTree $installedFolder
    Remove-Item -LiteralPath $installedFolder -Recurse
    $library = Scan
    $previous = @($library.games | Where-Object id -eq 'steam-100001')[0]
    Assert ($previous.installed -eq $false) 'uninstall transition updates installed state from manifest'
    [IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps/common/Installed Game')) | Out-Null
    [IO.File]::WriteAllText($manifest, '"appid" "100001" "name" "Installed Game" "StateFlags" "4" "installdir" "Installed Game"')
    $library = Scan
    $previous = @($library.games | Where-Object id -eq 'steam-100001')[0]
    Assert ($previous.installed -eq $true) 'reinstall transition updates installed state from manifest'

    $cachedPortrait = Join-Path $web 'covers/steam-200002.jpg'
    [IO.File]::WriteAllBytes($cachedPortrait, [byte[]](0xFF, 0xD8, 0xFF, 0xD9))
    [IO.Directory]::CreateDirectory((Join-Path $steam 'steamapps/common/Owned Game')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $steam 'steamapps/appmanifest_200002.acf'), '"appid" "200002" "name" "Owned Game" "StateFlags" "4" "installdir" "Owned Game"')
    $library = Scan
    $nowInstalled = @($library.games | Where-Object id -eq 'steam-200002')[0]
    Assert ($nowInstalled.installed -eq $true -and $nowInstalled.cover -eq 'covers/steam-200002.jpg') 'install transition keeps an existing owned portrait'

    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public sealed class OversizePortraitServer : IDisposable {
    private readonly TcpListener listener;
    private readonly Thread worker;
    public int Port { get; private set; }
    public volatile bool Served;
    public OversizePortraitServer() {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        worker = new Thread(Serve);
        worker.IsBackground = true;
        worker.Start();
    }
    private void Serve() {
        try {
            using (var client = listener.AcceptTcpClient())
            using (var stream = client.GetStream()) {
                var header = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nConnection: close\r\n\r\n");
                stream.Write(header, 0, header.Length);
                var chunk = new byte[32768];
                Served = true;
                for (int i = 0; i < 161; i++) stream.Write(chunk, 0, chunk.Length);
            }
        } catch (Exception) { }
    }
    public void Dispose() { listener.Stop(); worker.Join(5000); }
}
'@
    $server = New-Object OversizePortraitServer
    try {
        Remove-Item -LiteralPath $manifest
        Assert-SafeTree $installedFolder
        Remove-Item -LiteralPath $installedFolder -Recurse
        $library = Scan '' $false ("http://127.0.0.1:$($server.Port)")
        Assert ($server.Served) 'oversize artwork response was exercised'
        Assert (@($library.games).Count -eq 2) 'oversize artwork failure must not abort scan'
        Assert (-not (Test-Path -LiteralPath (Join-Path $web 'covers/steam-100001.jpg.new'))) 'oversize artwork failure must remove its temp file'
    } finally { $server.Dispose() }
    Write-Output 'PASS: owned source validation, cache fallback, installation transitions, portrait retention, and bounded download failure.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Assert-SafeTree $fixture; Remove-Item -LiteralPath $fixture -Recurse -Force }
}
