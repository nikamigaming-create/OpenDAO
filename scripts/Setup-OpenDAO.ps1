[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GameRoot,
    [string]$CacheRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'cache'),
    [string]$HavenRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Haven-Tools'),
    [string]$Area = 'lak100d',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not (Test-Path -LiteralPath $HavenRoot)) {
    & (Join-Path $PSScriptRoot 'Bootstrap-OpenDAO.ps1') -HavenRoot $HavenRoot
    if ($LASTEXITCODE -ne 0) { throw 'OpenDAO exporter bootstrap failed' }
}

& (Join-Path $PSScriptRoot 'Import-DAO.ps1') `
    -GameRoot $GameRoot `
    -CacheRoot $CacheRoot `
    -HavenRoot $HavenRoot `
    -Area $Area `
    -SkipBuild:$SkipBuild
if ($LASTEXITCODE -ne 0) { throw 'OpenDAO DAO import failed' }

Write-Host "OPENDAO_SETUP_READY root=$projectRoot profile=$(Join-Path $projectRoot 'godot\profiles\local.json')"
Write-Host 'Launch with: pwsh -File scripts/Start-OpenDAO.ps1 -Godot <Godot console executable>'
