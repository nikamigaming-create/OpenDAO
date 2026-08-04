[CmdletBinding()]
param(
    [string]$HavenRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\Haven-Tools'),
    [string]$HavenRepository = 'https://github.com/adarec1994/Haven-Tools.git',
    [string]$HavenRevision = '0765a5db7b5cea0cc5b405867deca7fa373921db'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$patch = Join-Path $projectRoot 'patches\haven-tools-opendao.patch'
if (-not (Test-Path -LiteralPath $patch)) { throw "Missing Haven patch: $patch" }
if (Test-Path -LiteralPath $HavenRoot) { throw "Refusing to overwrite existing Haven checkout: $HavenRoot" }

$parent = Split-Path $HavenRoot -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
git clone $HavenRepository $HavenRoot
if ($LASTEXITCODE -ne 0) { throw 'Haven Tools clone failed' }
git -C $HavenRoot checkout --detach $HavenRevision
if ($LASTEXITCODE -ne 0) { throw "Haven revision checkout failed: $HavenRevision" }
git -C $HavenRoot apply --check $patch
if ($LASTEXITCODE -ne 0) { throw 'Haven patch validation failed' }
git -C $HavenRoot apply $patch
if ($LASTEXITCODE -ne 0) { throw 'Haven patch application failed' }

Write-Host "OPENDAO_BOOTSTRAP_READY haven=$HavenRoot revision=$HavenRevision"
Write-Host 'Next: pwsh -File scripts/Import-DAO.ps1 -GameRoot <owned DAO install>'
