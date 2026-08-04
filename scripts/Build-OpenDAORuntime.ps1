[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GodotRuntime,
    [Parameter(Mandatory)]
    [string]$GodotConsole,
    [string]$OutputRoot,
    [string]$Version = 'dev'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$OutputRoot = if ($OutputRoot) { $OutputRoot } else { Join-Path $projectRoot 'artifacts\runtime' }
$godotProject = Join-Path $projectRoot 'godot'
foreach ($required in @($GodotRuntime, $GodotConsole, (Join-Path $godotProject 'project.godot'))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required runtime input not found: $required" }
}

$packageRoot = Join-Path $OutputRoot "OpenDAO-$Version-windows-x64"
if (Test-Path -LiteralPath $packageRoot) { throw "Refusing to overwrite runtime package: $packageRoot" }
New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

$pck = Join-Path $packageRoot 'OpenDAO.pck'
& $GodotConsole --headless --path $godotProject --export-pack 'Windows Portable' $pck
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $pck)) { throw 'Godot runtime pack export failed' }

Copy-Item -LiteralPath $GodotRuntime -Destination (Join-Path $packageRoot 'OpenDAO-engine.exe')
Copy-Item -LiteralPath $GodotConsole -Destination (Join-Path $packageRoot 'OpenDAO-engine_console.exe')
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses\GODOT-LICENSE.txt') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses\OPENDAO-LICENSE.txt') -Destination $packageRoot
Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\WINDOWS-RUNTIME.txt') -Destination (Join-Path $packageRoot 'README.txt')

$launcherSource = Join-Path $projectRoot 'native\launcher'
$launcherBuild = Join-Path $packageRoot '.launcher-build'
cmake -S $launcherSource -B $launcherBuild -A x64
if ($LASTEXITCODE -ne 0) { throw 'OpenDAO launcher configure failed' }
cmake --build $launcherBuild --config Release
if ($LASTEXITCODE -ne 0) { throw 'OpenDAO launcher build failed' }
Copy-Item -LiteralPath (Join-Path $launcherBuild 'Release\OpenDAO.exe') -Destination (Join-Path $packageRoot 'OpenDAO.exe')

$oldSmoke = $env:OPENDAO_SMOKE_EXIT
try {
    $env:OPENDAO_SMOKE_EXIT = '1'
    Push-Location $packageRoot
    try { & '.\OpenDAO-engine_console.exe' --headless --xr-mode off --main-pack '.\OpenDAO.pck' }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "OpenDAO runtime smoke test failed: $LASTEXITCODE" }
}
finally {
    if ($null -eq $oldSmoke) { Remove-Item Env:OPENDAO_SMOKE_EXIT -ErrorAction SilentlyContinue }
    else { $env:OPENDAO_SMOKE_EXIT = $oldSmoke }
}

$hashes = Get-ChildItem -LiteralPath $packageRoot -File | Sort-Object Name | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($_.Name)"
}
$hashes | Set-Content -LiteralPath (Join-Path $packageRoot 'SHA256SUMS.txt') -Encoding ascii
Remove-Item -LiteralPath $launcherBuild -Recurse -Force
Write-Host "OPENDAO_RUNTIME_PACKAGE_PASS path=$packageRoot"
