$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('GamesCoverflow-discovery-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path "$fixture/steam/steamapps/common/Test Game", "$fixture/result", "$fixture/desktop" | Out-Null
$manifest = @'
"AppState"
{
 "appid" "100001"
 "name" "Test & Unicode ™ Game"
 "StateFlags" "4"
 "installdir" "Test Game"
 "SizeOnDisk" "123456"
}
'@
[IO.File]::WriteAllText("$fixture/steam/steamapps/appmanifest_100001.acf", $manifest)
[IO.File]::WriteAllText("$fixture/steam/steamapps/appmanifest_228980.acf", $manifest.Replace('100001','228980').Replace('Test & Unicode ™ Game','Steamworks Common Redistributables'))
[IO.File]::WriteAllText("$fixture/steam/steamapps/appmanifest_100002.acf", $manifest.Replace('100001','100002').Replace('Test Game','Missing Game'))
$scanner = Join-Path $PSScriptRoot '../Scan-Library.ps1'
if (-not (Test-Path -LiteralPath $scanner)) { throw 'FAIL: library scanner is not implemented' }
& $scanner -SteamPath "$fixture/steam" -Destination "$fixture/result" -ShortcutRoots @("$fixture/desktop") -Offline
$library = Get-Content -LiteralPath "$fixture/result/library.json" -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($library.games).Count -ne 1) { throw 'FAIL: scanner must include installed games and exclude redistributables and missing installations' }
if ($library.games[0].id -ne 'steam-100001') { throw 'FAIL: stable game id' }
if ($library.games[0].name -ne 'Test & Unicode ™ Game') { throw 'FAIL: Unicode title preservation' }
$launch = Get-Content -LiteralPath "$fixture/result/launch.ini" -Raw
if ($launch -notmatch 'steam://rungameid/100001') { throw 'FAIL: launch URI' }
Write-Output 'PASS: discovery excludes tools/missing games, preserves Unicode, and creates launch mapping.'
