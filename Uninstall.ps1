$ErrorActionPreference = 'Stop'
$guid = '{B755C58D-7CB3-4AFE-B901-69B3AE21F8D4}'
$keys = @("HKCU:\Software\Classes\CLSID\$guid", "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace\$guid")
foreach ($key in $keys) {
    if (-not $key.EndsWith($guid)) { throw 'Unexpected registration path' }
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
}
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GamesShellUnnotify { [DllImport("shell32.dll")] public static extern void SHChangeNotify(uint e, uint f, IntPtr a, IntPtr b); }'
[GamesShellUnnotify]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
Write-Output 'Games has been removed from Explorer. Cached artwork and app files remain in LocalAppData\GamesCoverflow; they can be deleted after closing Games tabs and signing out. Your games were not changed.'
