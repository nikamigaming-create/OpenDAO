[CmdletBinding()]
param(
    [string]$Godot = "D:\code\gd\Godot_v4.6.3-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\godot")).Path
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot" }
$env:DAOPEN_MOBILE = "1"
Start-Process -FilePath $Godot -ArgumentList @(
    "--path", $project,
    "--xr-mode", "off",
    "--rendering-method", "mobile",
    "--resolution", "1280x720"
) -WorkingDirectory $project -PassThru
