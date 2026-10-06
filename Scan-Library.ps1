param(
    [string]$SteamPath = '',
    [string]$Destination = (Join-Path $PSScriptRoot 'web'),
    [string[]]$ShortcutRoots = @([Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop"),
    [switch]$AddGame,
    [string]$ArtworkId = '',
    [string]$ArtworkSource = '',
    [string]$SteamId = '',
    [string]$OwnedSourcePath = '',
    [switch]$Offline,
    [switch]$RefreshOwned,
    [string]$PortraitBaseUrl = 'https://cdn.akamai.steamstatic.com/steam/apps'
)
$ErrorActionPreference = 'Stop'
if ($ArtworkSource -and -not $ArtworkId) { throw 'ArtworkSource requires ArtworkId.' }
$utf8 = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force -Path $Destination, (Join-Path $Destination 'covers') | Out-Null
$lockPath = Join-Path $Destination 'scan.lock'
try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { exit 5 }
try {
    if ($ArtworkId) {
        try {
            $import = & (Join-Path $PSScriptRoot 'Import-Cover.ps1') -GameId $ArtworkId -SourcePath $ArtworkSource
            if ($import -eq 'cancelled') { exit 2 }
            if ($import -ne 'imported') { throw 'Cover import did not finish.' }
        } catch {
            [Console]::Error.WriteLine("Could not add cover art: " + $_.Exception.Message)
            exit 4
        }
    }
    if (-not $SteamPath) { $SteamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath }
    if (-not $SteamId -and $SteamPath) {
        $loginPath = Join-Path $SteamPath 'config/loginusers.vdf'
        if (Test-Path -LiteralPath $loginPath) {
            $loginText = [IO.File]::ReadAllText($loginPath)
            $login = [regex]::Match($loginText, '"(7656119[0-9]{10})"\s*\{[^}]*"AutoLogin"\s+"1"', 'Singleline')
            if ($login.Success) { $SteamId = $login.Groups[1].Value }
        }
    }
    $games = New-Object System.Collections.Generic.List[object]
    $targets = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    function Field([string]$text, [string]$key) {
        $m = [regex]::Match($text, '"' + [regex]::Escape($key) + '"\s+"([^"\r\n]*)"')
        if ($m.Success) { return $m.Groups[1].Value.Replace('\\','\') }
        return ''
    }
    $details = $null
    $detailsPath = Join-Path $Destination 'game-details.json'
    if (Test-Path -LiteralPath $detailsPath) {
        try { $details = Get-Content -LiteralPath $detailsPath -Raw | ConvertFrom-Json }
        catch { $details = $null }
    }
    function Detail([string]$id, [string]$key) {
        if (-not $details) { return '' }
        $record = $details.PSObject.Properties[$id]
        if (-not $record -or -not $record.Value) { return '' }
        $value = $record.Value.PSObject.Properties[$key]
        if ($value -and $value.Value -is [string]) { return $value.Value }
        return ''
    }
    function Default-Cover([string]$id) {
        $relative = Detail $id 'defaultCover'
        if ($relative -notmatch '^covers/[a-zA-Z0-9._-]+\.(png|jpg|jpeg|bmp)$') { return '' }
        if (Test-Path -LiteralPath (Join-Path $Destination $relative) -PathType Leaf) { return $relative }
        return ''
    }
    function Custom-Cover([string]$id) {
        $source = Join-Path $PSScriptRoot "User Covers/$id.png"
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return '' }
        $relative = "covers/$id.png"
        Copy-Item -LiteralPath $source -Destination (Join-Path $Destination $relative) -Force
        return ($relative + '?v=' + (Get-Item -LiteralPath $source).LastWriteTimeUtc.Ticks)
    }
    function Website([string]$id) {
        if ($id -match '^steam-([0-9]+)$') { return "https://store.steampowered.com/app/$($Matches[1])/" }
        return ''
    }
    function Add-Launch([string]$id,[string]$target,[string]$folder,[string]$website) {
        if ($target -match '[\r\n]' -or $folder -match '[\r\n]') { throw 'Invalid launch target' }
        $entry = "[$id]`r`ntarget=$target`r`nfolder=$folder`r`n"
        if ($website) { $entry += "website=$website`r`n" }
        $targets.Add($entry)
    }
    function Read-OwnedGames([string]$path, [string]$steamId) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        try {
            $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($data.steamId -cne $steamId -or $data.complete -ne $true -or $null -eq $data.games) { return $null }
            $valid = New-Object System.Collections.Generic.List[object]
            $known = @{}
            foreach ($game in @($data.games)) {
                $appId = [string]$game.appid
                $name = [string]$game.name
                if ($appId -notmatch '^[1-9][0-9]*$' -or -not $name.Trim() -or $known.ContainsKey($appId)) { continue }
                if ([string]$game.type -match '^(?i:dlc|tool|software|demo|video|music|application)$') { continue }
                $known[$appId] = $true
                $valid.Add([pscustomobject]@{ appid=$appId; name=$name.Trim() })
            }
            if ($valid.Count -eq 0) { return $null }
            return ,@($valid.ToArray())
        } catch { return $null }
    }
    function Save-OwnedGames([string]$path, [string]$steamId, [object[]]$games, [string]$source) {
        $snapshot = @{ steamId=$steamId; complete=$true; source=$source; refreshedAt=[DateTime]::UtcNow.ToString('o'); games=@($games) } | ConvertTo-Json -Depth 5
        $temp = "$path.new"
        [IO.File]::WriteAllText($temp, $snapshot, $utf8)
        Move-Item -LiteralPath $temp -Destination $path -Force
    }
    $ownedPath = Join-Path $Destination 'owned-steam.json'
    $ownedAttemptPath = Join-Path $Destination 'owned-steam-attempt.txt'
    $ownedGames = $null
    if ($SteamId -match '^7656119[0-9]{10}$') {
        $ownedGames = Read-OwnedGames $ownedPath $SteamId
        if ($OwnedSourcePath) {
            $imported = Read-OwnedGames $OwnedSourcePath $SteamId
            if ($null -ne $imported) {
                $ownedGames = $imported
                Save-OwnedGames $ownedPath $SteamId $ownedGames 'authenticated-export'
                [IO.File]::WriteAllText($ownedAttemptPath, [DateTime]::UtcNow.ToString('o'), $utf8)
            } else { [Console]::Error.WriteLine('Owned Steam source unavailable or invalid; retaining cached games.') }
        } elseif (-not $Offline -and ($RefreshOwned -or -not (Test-Path -LiteralPath $ownedAttemptPath) -or ((Get-Item -LiteralPath $ownedAttemptPath).LastWriteTimeUtc -lt [DateTime]::UtcNow.AddHours(-24)))) {
            try {
                [IO.File]::WriteAllText($ownedAttemptPath, [DateTime]::UtcNow.ToString('o'), $utf8)
                $url = "https://steamcommunity.com/profiles/$SteamId/games?tab=all&xml=1"
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 12
                [xml]$xml = $response.Content
                if ($xml.DocumentElement.LocalName -ne 'gamesList' -or [string]$xml.gamesList.steamID64 -ne $SteamId) { throw 'Not a games feed for this account.' }
                $fromXml = New-Object System.Collections.Generic.List[object]
                foreach ($game in @($xml.gamesList.games.game)) {
                    $fromXml.Add([pscustomobject]@{ appid=[string]$game.appID; name=[string]$game.name; type='game' })
                }
                $candidatePath = Join-Path $Destination 'owned-steam-feed.new.json'
                [IO.File]::WriteAllText($candidatePath, (@{ steamId=$SteamId; complete=$true; games=@($fromXml) } | ConvertTo-Json -Depth 5), $utf8)
                $refreshed = Read-OwnedGames $candidatePath $SteamId
                Remove-Item -LiteralPath $candidatePath -ErrorAction SilentlyContinue
                if ($null -eq $refreshed) { throw 'Empty or invalid games feed.' }
                $ownedGames = $refreshed
                Save-OwnedGames $ownedPath $SteamId $ownedGames 'steam-community-xml'
            } catch { [Console]::Error.WriteLine('Steam owned games refresh unavailable; retaining cached games: ' + $_.Exception.Message) }
        }
    }
    $libraries = New-Object System.Collections.Generic.List[string]
    if ($SteamPath -and (Test-Path -LiteralPath $SteamPath)) {
        $libraries.Add($SteamPath)
        $vdf = Join-Path $SteamPath 'steamapps/libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            $text = [IO.File]::ReadAllText($vdf)
            foreach ($m in [regex]::Matches($text, '"path"\s+"([^"\r\n]+)"')) {
                $p = $m.Groups[1].Value.Replace('\\','\')
                if (-not $libraries.Contains($p)) { $libraries.Add($p) }
            }
        }
    }
    foreach ($lib in $libraries) {
        foreach ($manifest in Get-ChildItem -LiteralPath (Join-Path $lib 'steamapps') -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue) {
            $text = [IO.File]::ReadAllText($manifest.FullName)
            $appId = Field $text 'appid'
            $name = Field $text 'name'
            $install = Field $text 'installdir'
            $flags = Field $text 'StateFlags'
            if ($appId -notmatch '^\d+$' -or -not $name -or $seen.ContainsKey($appId)) { continue }
            if ($appId -eq '228980' -or $name -match 'Redistributable|Steamworks|Dedicated Server|Proton|Steam Linux') { continue }
            if ($flags -notmatch '^\d+$' -or (([int]$flags -band 4) -eq 0)) { continue }
            $folder = Join-Path (Join-Path $lib 'steamapps/common') $install
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
            $seen[$appId] = $true
            $id = "steam-$appId"
            $cover = ''
            $cache = Join-Path $SteamPath "appcache/librarycache/$appId"
            $image = Get-ChildItem -LiteralPath $cache -Filter 'library_600x900*' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $image) { $image = Get-ChildItem -LiteralPath $cache -Filter 'library_capsule*' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if (-not $image) { $image = Get-ChildItem -LiteralPath (Join-Path $SteamPath 'appcache/librarycache') -Filter "${appId}_library_600x900*" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if ($image) {
                $cover = "covers/$id$($image.Extension)"
                Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $Destination $cover) -Force
            } elseif (Test-Path -LiteralPath (Join-Path $Destination "covers/$id.jpg") -PathType Leaf) {
                $cover = "covers/$id.jpg"
            }
            $customCover = Custom-Cover $id
            if ($customCover) { $cover = $customCover }
            elseif (-not $cover) { $cover = Default-Cover $id }
            $bytes = Field $text 'SizeOnDisk'
            $size = if ($bytes -match '^\d+$') { [math]::Round(([double]$bytes / 1GB),1) } else { 0 }
            $played = Field $text 'LastPlayed'
            $games.Add([pscustomobject]@{ id=$id; name=$name; platform='Steam'; cover=$cover; customCover=[bool]$customCover; installed=$true; sizeGB=$size; lastPlayed=$played; folder=$folder })
            Add-Launch $id "steam://rungameid/$appId" $folder (Website $id)
        }
    }
    $downloadedArt = 0
    foreach ($owned in @($ownedGames)) {
        if (-not $owned) { continue }
        $appId = [string]$owned.appid
        if ($seen.ContainsKey($appId)) { continue }
        $seen[$appId] = $true
        $id = "steam-$appId"
        $cover = ''
        $cache = Join-Path $SteamPath "appcache/librarycache/$appId"
        $image = Get-ChildItem -LiteralPath $cache -Filter 'library_600x900*' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $image) { $image = Get-ChildItem -LiteralPath (Join-Path $SteamPath 'appcache/librarycache') -Filter "${appId}_library_600x900*" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if ($image) {
            $cover = "covers/$id$($image.Extension)"
            Copy-Item -LiteralPath $image.FullName -Destination (Join-Path $Destination $cover) -Force
        } else {
            $downloadPath = Join-Path $Destination "covers/$id.jpg"
            if (Test-Path -LiteralPath $downloadPath -PathType Leaf) { $cover = "covers/$id.jpg" }
            elseif (-not $Offline -and $downloadedArt -lt 12) {
                $downloadedArt++
                $request = $null
                $response = $null
                $stream = $null
                $output = $null
                $downloadSucceeded = $false
                try {
                    $request = [Net.HttpWebRequest]::Create("$PortraitBaseUrl/$appId/library_600x900.jpg")
                    $request.Timeout = 4000
                    $request.ReadWriteTimeout = 4000
                    $response = $request.GetResponse()
                    if ($response.ContentType -notmatch '^image/' -or $response.ContentLength -gt 5MB) { throw 'No suitable portrait.' }
                    $stream = $response.GetResponseStream()
                    $output = [IO.File]::Create("$downloadPath.new")
                    $buffer = New-Object byte[] 32768
                    $length = 0
                    while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $length += $read
                        if ($length -gt 5MB) { throw 'Portrait exceeds size limit.' }
                        $output.Write($buffer, 0, $read)
                    }
                    $output.Dispose(); $output = $null
                    Move-Item -LiteralPath "$downloadPath.new" -Destination $downloadPath -Force
                    $cover = "covers/$id.jpg"
                    $downloadSucceeded = $true
                } catch { } finally {
                    if ($output) { try { $output.Dispose() } catch { } }
                    if ($stream) { try { $stream.Dispose() } catch { } }
                    if ($response) { try { $response.Dispose() } catch { } }
                    if (-not $downloadSucceeded) {
                        try { Remove-Item -LiteralPath "$downloadPath.new" -ErrorAction Stop } catch { }
                    }
                }
            }
        }
        $customCover = Custom-Cover $id
        if ($customCover) { $cover = $customCover }
        elseif (-not $cover) { $cover = Default-Cover $id }
        $games.Add([pscustomobject]@{ id=$id; name=[string]$owned.name; platform='Steam'; cover=$cover; customCover=[bool]$customCover; installed=$false; sizeGB=0; lastPlayed='0'; folder='' })
        Add-Launch $id "steam://install/$appId" '' (Website $id)
    }
    $wsh = New-Object -ComObject WScript.Shell
    $shortcuts = @()
    foreach ($root in $ShortcutRoots) {
        if ($root -and (Test-Path -LiteralPath $root)) { $shortcuts += @(Get-ChildItem -LiteralPath $root -Filter '*.lnk' -File -ErrorAction SilentlyContinue) }
    }
    $customDir = Join-Path $PSScriptRoot 'My Games'
    if ($AddGame) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Add a game executable or shortcut'
        $dialog.Filter = 'Games and shortcuts (*.exe;*.lnk)|*.exe;*.lnk'
        $dialog.DereferenceLinks = $false
        if ($dialog.ShowDialog() -eq 'OK') {
            New-Item -ItemType Directory -Force -Path $customDir | Out-Null
            $source = $dialog.FileName
            if ([IO.Path]::GetExtension($source) -eq '.lnk') {
                Copy-Item -LiteralPath $source -Destination $customDir -Force
            } else {
                $link = $wsh.CreateShortcut((Join-Path $customDir ([IO.Path]::GetFileNameWithoutExtension($source) + '.lnk')))
                $link.TargetPath = $source
                $link.WorkingDirectory = [IO.Path]::GetDirectoryName($source)
                $link.Save()
            }
        }
        $dialog.Dispose()
    }
    if (Test-Path -LiteralPath $customDir) { $shortcuts += @(Get-ChildItem -LiteralPath $customDir -Filter '*.lnk' -File) }
    foreach ($file in $shortcuts) {
        $link = $wsh.CreateShortcut($file.FullName)
        $target = $link.TargetPath
        $explicit = $file.DirectoryName -eq $customDir
        if (-not $explicit -and $target -notmatch '(?i)[\\/]games[\\/]') { continue }
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        if (-not $explicit -and $target -match '(?i)unins|crash|launcher|update') { continue }
        if ($seen.ContainsKey($target)) { continue }
        $seen[$target] = $true
        $sha = [Security.Cryptography.SHA256]::Create()
        $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($file.FullName)))).Replace('-','').Substring(0,16).ToLowerInvariant()
        $sha.Dispose()
        $id = "local-$hash"
        $name = $file.BaseName
        $cover = ''
        $customCover = Join-Path $customDir "$name.jpg"
        if (Test-Path -LiteralPath $customCover) { $cover="covers/$id.jpg"; Copy-Item -LiteralPath $customCover -Destination (Join-Path $Destination $cover) -Force }
        $importedCover = Custom-Cover $id
        if ($importedCover) { $cover = $importedCover }
        elseif (-not $cover) { $cover = Default-Cover $id }
        $folder = Split-Path -Parent $target
        $games.Add([pscustomobject]@{ id=$id; name=$name; platform='Windows'; cover=$cover; customCover=[bool]$importedCover; installed=$true; sizeGB=0; lastPlayed='0'; folder=$folder })
        Add-Launch $id $file.FullName $folder (Website $id)
    }
    $sorted = @($games | Sort-Object name)
    $data = @{ games=$sorted; updated=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $Destination 'launch.ini.new'), ($targets -join "`r`n"), [Text.Encoding]::Unicode)
    [IO.File]::WriteAllText((Join-Path $Destination 'library.json.new'), $data, $utf8)
    Move-Item -LiteralPath (Join-Path $Destination 'launch.ini.new') -Destination (Join-Path $Destination 'launch.ini') -Force
    Move-Item -LiteralPath (Join-Path $Destination 'library.json.new') -Destination (Join-Path $Destination 'library.json') -Force
    Write-Output "Found $($sorted.Count) games ($(@($sorted | Where-Object installed).Count) installed)."
} finally { $lock.Dispose() }
