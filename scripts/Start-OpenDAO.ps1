[CmdletBinding()]
param(
    [string]$Godot = "D:\code\gd\Godot_v4.6.3-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\godot")).Path
if (-not (Test-Path -LiteralPath $Godot)) { throw "Godot not found: $Godot" }
Start-Process -FilePath $Godot -ArgumentList @("--path", $project) -WorkingDirectory $project -PassThru
