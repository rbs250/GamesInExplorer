param(
    [Parameter(Mandatory=$true)][string]$SdkPath,
    [string]$BuildPath = (Join-Path $PSScriptRoot '.build')
)
$ErrorActionPreference = 'Stop'
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Install Visual Studio C++ x64 Build Tools first.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Install Visual Studio C++ x64 Build Tools first.' }
$sdk = (Resolve-Path -LiteralPath $SdkPath).Path
$include = Join-Path $sdk 'build/native/include/WebView2.h'
$loader = Join-Path $sdk 'build/native/x64/WebView2LoaderStatic.lib'
if (-not (Test-Path -LiteralPath $include) -or -not (Test-Path -LiteralPath $loader)) { throw 'SdkPath must point to an extracted Microsoft.Web.WebView2 NuGet package.' }
New-Item -ItemType Directory -Force -Path $BuildPath | Out-Null
$build = (Resolve-Path -LiteralPath $BuildPath).Path
$root = $PSScriptRoot
$vc = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$command = @"
@echo off
call "$vc" >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /MT /utf-8 "$root\tests\steam_target.cpp" /Fe:"$build\steam_target.exe"
if errorlevel 1 exit /b 1
"$build\steam_target.exe"
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /MT /DUNICODE /D_UNICODE /utf-8 /I"$sdk\build\native\include" "$root\tests\smoke.cpp" /Fe:"$build\smoke.exe" /link ole32.lib shell32.lib shlwapi.lib uuid.lib user32.lib
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /MT /DUNICODE /D_UNICODE /utf-8 /LD /I"$sdk\build\native\include" "$root\src\shell.cpp" "$root\src\view.cpp" /Fe:"$build\GamesCoverflow.dll" /link /DEF:"$root\src\exports.def" "$sdk\build\native\x64\WebView2LoaderStatic.lib" user32.lib gdi32.lib ole32.lib oleaut32.lib shell32.lib shlwapi.lib uuid.lib advapi32.lib version.lib
if errorlevel 1 exit /b 1
"$build\smoke.exe" "$build\GamesCoverflow.dll"
exit /b %errorlevel%
"@
[IO.File]::WriteAllText((Join-Path $build 'compile.cmd'), $command, [Text.Encoding]::ASCII)
Push-Location $build
try { & $env:ComSpec /d /c (Join-Path $build 'compile.cmd'); if ($LASTEXITCODE) { throw 'Native build or smoke test failed.' } }
finally { Pop-Location }
Write-Output "PASS: native build and smoke tests. DLL: $build\GamesCoverflow.dll"
