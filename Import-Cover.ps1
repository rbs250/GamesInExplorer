param(
    [Parameter(Mandatory=$true)][string]$GameId,
    [string]$SourcePath = ''
)
$ErrorActionPreference = 'Stop'
if ($GameId -cnotmatch '^(steam-[0-9]{1,74}|local-[0-9a-f]{16})$') { throw 'Invalid game ID.' }
$launchPath = Join-Path $PSScriptRoot 'web/launch.ini'
if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) { throw 'The game library is unavailable. Refresh it first.' }
$launch = [IO.File]::ReadAllText($launchPath)
if ($launch -cnotmatch ('(?m)^\[' + [regex]::Escape($GameId) + '\]\r?$')) { throw 'This game is no longer in the library. Refresh it first.' }

if (-not $SourcePath) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = 'Choose cover art'
        $dialog.Filter = 'Images (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
        $pictures = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures)
        if ($pictures -and (Test-Path -LiteralPath $pictures -PathType Container)) { $dialog.InitialDirectory = $pictures }
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return 'cancelled' }
        $SourcePath = $dialog.FileName
    } finally { $dialog.Dispose() }
}
if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) { throw 'The selected image no longer exists.' }
$extension = [IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
if ($extension -notin @('.png','.jpg','.jpeg','.bmp')) { throw 'Choose a PNG, JPEG, or BMP image.' }
$file = Get-Item -LiteralPath $SourcePath
if ($file.Length -gt 25MB) { throw 'The selected image is too large (25 MB maximum).' }

Add-Type -AssemblyName System.Drawing
$coverDir = Join-Path $PSScriptRoot 'User Covers'
$output = Join-Path $coverDir "$GameId.png"
$temporary = $null
$image = $null
$bitmap = $null
$graphics = $null
try {
    try { $image = [Drawing.Image]::FromFile($file.FullName) }
    catch { throw 'The selected file could not be read as an image. Choose a valid PNG, JPEG, or BMP.' }
    if ($image.Width -lt 1 -or $image.Height -lt 1 -or $image.Width -gt 20000 -or $image.Height -gt 20000 -or ([long]$image.Width * $image.Height) -gt 100000000) {
        throw 'The selected image dimensions are unsupported.'
    }
    $scale = [Math]::Min(1.0, 1200.0 / [Math]::Max($image.Width, $image.Height))
    $width = [Math]::Max(1, [int][Math]::Round($image.Width * $scale))
    $height = [Math]::Max(1, [int][Math]::Round($image.Height * $scale))
    $bitmap = New-Object Drawing.Bitmap($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($image, 0, 0, $width, $height)
    $graphics.Dispose(); $graphics = $null
    New-Item -ItemType Directory -Force -Path $coverDir | Out-Null
    $temporary = Join-Path $coverDir ('.' + $GameId + '-' + [guid]::NewGuid().ToString('N') + '.png')
    $bitmap.Save($temporary, [Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose(); $bitmap = $null
    $image.Dispose(); $image = $null
    if (Test-Path -LiteralPath $output) { [IO.File]::Replace($temporary, $output, $null) }
    else { [IO.File]::Move($temporary, $output) }
    $temporary = $null
    return 'imported'
} finally {
    if ($graphics) { $graphics.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
    if ($image) { $image.Dispose() }
    if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Force }
}
