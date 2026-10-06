param([switch]$NoOpen)
$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess) { throw 'Run the installer in 64-bit PowerShell.' }
$guid = '{B755C58D-7CB3-4AFE-B901-69B3AE21F8D4}'
$destination = Join-Path $env:LOCALAPPDATA 'GamesCoverflow'
New-Item -ItemType Directory -Force -Path $destination | Out-Null
$dllSource = Join-Path $PSScriptRoot '.build/GamesCoverflow.dll'
if (-not (Test-Path -LiteralPath $dllSource)) { throw 'Build first with Build.ps1 -SdkPath <extracted WebView2 SDK path>.' }
$dllHash = (Get-FileHash -LiteralPath $dllSource -Algorithm SHA256).Hash.Substring(0,12).ToLowerInvariant()
$dllPath = Join-Path $destination "GamesCoverflow-$dllHash.dll"
if (-not (Test-Path -LiteralPath $dllPath)) { Copy-Item -LiteralPath $dllSource -Destination $dllPath }
foreach ($name in @('Scan-Library.ps1','Import-Cover.ps1','Uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destination $name) -Force }
& (Join-Path $PSScriptRoot 'Prepare-WebRuntime.ps1') -Destination (Join-Path $destination 'web')
& (Join-Path $destination 'Scan-Library.ps1')
$key = "HKCU:\Software\Classes\CLSID\$guid"
New-Item -Path "$key\InProcServer32" -Force | Out-Null
Set-Item -LiteralPath $key -Value 'Games'
Set-Item -LiteralPath "$key\InProcServer32" -Value $dllPath
New-ItemProperty -LiteralPath "$key\InProcServer32" -Name 'ThreadingModel' -Value 'Apartment' -PropertyType String -Force | Out-Null
New-ItemProperty -LiteralPath $key -Name 'System.IsPinnedToNameSpaceTree' -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $key -Name 'SortOrderIndex' -Value 85 -PropertyType DWord -Force | Out-Null
New-ItemProperty -LiteralPath $key -Name 'InfoTip' -Value 'Your game collection in Cover Flow' -PropertyType String -Force | Out-Null
New-Item -Path "$key\DefaultIcon" -Force | Out-Null
Set-Item -LiteralPath "$key\DefaultIcon" -Value "$env:SystemRoot\System32\imageres.dll,-186"
New-Item -Path "$key\ShellFolder" -Force | Out-Null
New-ItemProperty -LiteralPath "$key\ShellFolder" -Name Attributes -Value 0x28000000 -PropertyType DWord -Force | Out-Null
New-Item -Path "$key\shell\open\command" -Force | Out-Null
# Use the same explicit namespace target as the shortcut. The generic Folder
# DelegateExecute handler can return success without opening this custom root.
Set-Item -LiteralPath "$key\shell" -Value 'open'
Set-Item -LiteralPath "$key\shell\open\command" -Value ('"{0}\explorer.exe" "shell:::{1}"' -f $env:SystemRoot, $guid)
Remove-ItemProperty -LiteralPath "$key\shell\open\command" -Name 'DelegateExecute' -ErrorAction SilentlyContinue
$namespace = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$guid"
New-Item -Path $namespace -Force | Out-Null
Set-Item -LiteralPath $namespace -Value 'Games'
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GamesShellNotify { [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint e, uint f, IntPtr a, IntPtr b); }'
[GamesShellNotify]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
$wsh = New-Object -ComObject WScript.Shell
$link = $wsh.CreateShortcut((Join-Path $PSScriptRoot 'Open Games.lnk'))
$link.TargetPath = "$env:SystemRoot\explorer.exe"
$link.Arguments = "shell:::$guid"
$link.Description = 'Browse your game collection inside Windows Explorer'
$link.IconLocation = "$env:SystemRoot\System32\imageres.dll,185"
$link.Save()
Write-Output 'Installed Games in File Explorer. Open the Games item in the Explorer sidebar or on the desktop.'
if (-not $NoOpen) { Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "shell:::$guid" }
