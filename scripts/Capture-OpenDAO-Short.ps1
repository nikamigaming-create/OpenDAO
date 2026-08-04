[CmdletBinding()]
param(
    [ValidateSet("water", "town", "door", "scout")]
    [string]$Short = "water",
    [switch]$Mobile,
    [string]$Godot = "D:\code\gd\Godot_v4.6.3-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\godot")).Path
$artifacts = Join-Path (Split-Path $PSScriptRoot -Parent) "artifacts\shorts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$prefix = if ($Mobile) { "opendao-mobile-$Short" } else { "opendao-$Short" }
$movie = Join-Path $artifacts ("{0}-{1}.avi" -f $prefix, $stamp)
$share = Join-Path $artifacts ("{0}-{1}-720p.mp4" -f $prefix, $stamp)
$log = Join-Path $artifacts ("{0}-{1}.log" -f $prefix, $stamp)
$env:DAOPEN_TOUR = $Short
if ($Mobile) { $env:DAOPEN_MOBILE = "1" }
try {
    $renderer = if ($Mobile) { "mobile" } else { "forward_plus" }
    & $Godot --path $project --xr-mode off --rendering-method $renderer --write-movie $movie --fixed-fps 30 --quit-after 1800 --resolution 1280x720 --log-file $log
    if ($LASTEXITCODE -ne 0) { throw "Godot capture failed with exit code $LASTEXITCODE" }
} finally {
    Remove-Item Env:DAOPEN_TOUR -ErrorAction SilentlyContinue
    Remove-Item Env:DAOPEN_MOBILE -ErrorAction SilentlyContinue
}
& ffmpeg -y -i $movie -vf "scale=1280:720:flags=lanczos" -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -an $share | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Shareable MP4 encoding failed with exit code $LASTEXITCODE" }
Remove-Item -LiteralPath $movie -Force
Write-Output $share
