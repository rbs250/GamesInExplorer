param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [string]$Source = (Join-Path $PSScriptRoot 'web')
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
foreach ($name in @('index.html','style.css','app.js')) {
    Copy-Item -LiteralPath (Join-Path $Source $name) -Destination $Destination -Force
}
foreach ($name in @('library','game-details')) {
    $runtime = Join-Path $Destination "$name.json"
    if (-not (Test-Path -LiteralPath $runtime)) {
        Copy-Item -LiteralPath (Join-Path $Source "$name.template.json") -Destination $runtime
    }
}
