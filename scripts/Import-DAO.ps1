[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,
    [string]$CacheRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'cache'),
    [string]$HavenRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Haven-Tools'),
    [string]$Area = "lak100d",
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$havenExe = Join-Path $havenRoot "build\Release\HavenTools.exe"
$geometryRim = Join-Path $GameRoot "packages\core\env\lak100d\lak100d.rim"
$gameplayRim = Join-Path $GameRoot "modules\single player\data\al_arl01al_redcliffe_villag.rim"

foreach ($path in @($GameRoot, $geometryRim, $gameplayRim, $havenRoot)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required DAO path not found: $path" }
}

if (-not $SkipBuild) {
    cmake -S $havenRoot -B (Join-Path $havenRoot "build") -A x64
    if ($LASTEXITCODE -ne 0) { throw "Haven configure failed" }
    cmake --build (Join-Path $havenRoot "build") --config Release
    if ($LASTEXITCODE -ne 0) { throw "Haven build failed" }
}
if (-not (Test-Path -LiteralPath $havenExe)) { throw "Modified Haven executable not found: $havenExe" }

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$output = Join-Path $CacheRoot "import-$stamp"
New-Item -ItemType Directory -Path $output -Force | Out-Null
& $havenExe --batch-level $GameRoot $geometryRim $output $gameplayRim
if ($LASTEXITCODE -ne 0) { throw "DAO import failed" }

$areaRoot = Join-Path $output $Area
$areaFile = Join-Path $areaRoot "$Area.havenarea"
if (-not (Test-Path -LiteralPath $areaFile)) { throw "Imported area manifest missing: $areaFile" }

$profile = [ordered]@{
    schema = 1
    game_root = $GameRoot.Replace('\', '/')
    area_file = $areaFile.Replace('\', '/')
    area_root = $areaRoot.Replace('\', '/')
    area = $Area
    display_name = "Redcliffe Village"
}
$profilePath = Join-Path $projectRoot "godot\profiles\local.json"
$profile | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM
Write-Host "DAOPEN_IMPORT_READY profile=$profilePath area=$areaFile"
