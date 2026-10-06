# Games in Explorer

A Windows x64 File Explorer virtual folder for browsing installed games and an
optional Steam ownership snapshot on a cover shelf or grid. It uses a native C++
Shell extension, a local WebView2 page, and PowerShell library scanning. The
project is independent, inspired by Cover Flow, and is not endorsed by Apple,
Microsoft, Valve, or OpenAI. Built with assistance from GPT-6 Astra.

The public source includes empty collection and game-details templates. On
first install, they become private runtime files and the scanner finds
installed Steam games and game shortcuts.
Covers are copied into each user's local cache from their own Steam cache, may
be fetched from Steam's art CDN for owned titles, or can be chosen by the user.
No game art, screenshots, synopses, or personal library data is bundled. Games
without artwork get a title placeholder. Newly discovered games show basic
installation and source information unless the user adds local metadata.

## Requirements and build

- Windows x64 with Microsoft Edge WebView2 Runtime.
- Visual Studio 2022 C++ x64 Build Tools with a Windows SDK.
- Windows PowerShell 5.1.
- Extract the official [Microsoft.Web.WebView2 NuGet package, version
  1.0.4258.31](https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4258.31)
  outside this source folder. Rename the downloaded `.nupkg` to `.zip` if needed
  and extract it. Pass the directory containing `build/native/include` as
  `-SdkPath`.

```powershell
./Build.ps1 -SdkPath C:\path\to\Microsoft.Web.WebView2.1.0.4258.31
```

The script builds into `.build/` and runs native smoke tests. It never needs a
parent workspace. The SDK and built binaries are excluded from this source
package. Review [third-party notices](THIRD_PARTY_NOTICES.md) for the separate
WebView2 terms.

## Install, use, remove

After building, run `Install.cmd` in ordinary Windows Explorer for the current
user. It registers the Games virtual folder in Explorer, creates an Open Games
shortcut, and scans the local library. No administrator access or background
server is required. Close open Games tabs before updating. `Uninstall.cmd`
removes this project's Explorer registration. It leaves installed games and
local cache under `%LOCALAPPDATA%\GamesCoverflow` alone.

Refresh rescans installations and shortcuts. `+` adds an executable or shortcut.
You can browse with the arrow keys, search with `/`, switch to a grid, open game
details, choose a cover, and launch installed games. Steam titles in an imported
owned list that are not installed show an **Install in Steam** action.

The Steam owned list is a snapshot, not authenticated automatic sync. The
scanner may refresh it from a public Steam XML games feed when that feed is
available. A private account needs a user supplied export; this project does
not extract account credentials. Create a JSON file matching
[`examples/owned-steam.example.json`](examples/owned-steam.example.json), with
your own SteamID64 and your own game IDs, then run:

```powershell
& "$env:LOCALAPPDATA\GamesCoverflow\Scan-Library.ps1" -SteamId YOUR_STEAMID64 -OwnedSourcePath C:\path\to\owned.json
```

The scanner writes personal runtime data into ignored `web/*.json` runtime
files when run in source. The tracked templates remain empty. Keep cached art,
ownership exports, and custom shortcuts out of commits. The installed app uses
its own LocalAppData copy. Explorer's toolbar search and ordinary file
management commands do not work inside this virtual cover surface; use its own
search and controls. Removing the extension does not remove game files.

## Tests and license

`Build.ps1` runs the native tests. PowerShell fixtures can be run individually
from `tests/`; they use synthetic games in temporary folders. Run
`python tests/interface_test.py` for the synthetic browser smoke test with
Playwright and Edge installed. The original
project source is MIT licensed (see [LICENSE](LICENSE)). Publisher artwork and
other third-party material are outside that license.
