[CmdletBinding()]
param(
    [ValidateSet("water", "town")]
    [string]$Short = "town",
    [string]$Godot = "D:\code\gd\Godot_v4.6.3-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$project = (Resolve-Path (Join-Path $PSScriptRoot "..\godot")).Path
$artifacts = Join-Path (Split-Path $PSScriptRoot -Parent) "artifacts\shorts"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$log = Join-Path $artifacts ("opendao-xr-simulator-{0}-{1}.log" -f $Short, $stamp)
$movie = Join-Path $artifacts ("opendao-xr-simulator-{0}-{1}-720p.mp4" -f $Short, $stamp)
$env:DAOPEN_TOUR = $Short
$env:DAOPEN_XR_CAPTURE = "1"
$godotProcess = $null
try {
    $godotProcess = Start-Process -FilePath $Godot -ArgumentList @(
        "--path", $project, "--xr-mode", "on", "--resolution", "1280x720", "--log-file", $log
    ) -WorkingDirectory $project -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $log) {
            $tail = Get-Content -LiteralPath $log -Raw -ErrorAction SilentlyContinue
            if ($tail -match "OPENDAO_TOUR_BEGIN" -and $tail -match "OPENDAO_XR ready=true") { break }
        }
        Start-Sleep -Milliseconds 100
    }
    if ((Get-Date) -ge $deadline) { throw "Meta XR Simulator tour did not reach the capture gate." }
    & ffmpeg -hide_banner -loglevel warning -y -f gdigrab -framerate 30 -draw_mouse 0 `
        -i "title=OpenDAO XR Spectator" -t 6 -vf "scale=1280:720:flags=lanczos" `
        -c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -an $movie
    if ($LASTEXITCODE -ne 0) { throw "Exact-title XR simulator recording failed with exit code $LASTEXITCODE" }
    $runtimeLog = Get-Content -LiteralPath $log -Raw
    if ($runtimeLog -notmatch "Meta XR Simulator" -or $runtimeLog -notmatch "OPENDAO_XR ready=true" -or $runtimeLog -notmatch "OPENDAO_XR_SPECTATOR ready=true") {
        throw "The recording was not backed by the active Meta XR Simulator runtime."
    }
} finally {
    Remove-Item Env:DAOPEN_TOUR -ErrorAction SilentlyContinue
    Remove-Item Env:DAOPEN_XR_CAPTURE -ErrorAction SilentlyContinue
    if ($null -ne $godotProcess -and -not $godotProcess.HasExited) {
        Stop-Process -Id $godotProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
Write-Output $movie
