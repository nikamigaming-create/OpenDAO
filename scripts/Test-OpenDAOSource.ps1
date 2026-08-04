[CmdletBinding()]
param(
    [switch]$ValidateHavenPatch
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$failures = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    foreach ($error in $errors) { $failures.Add("$($_.Name): $($error.Message)") }
}

python -m py_compile (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.py' | Select-Object -ExpandProperty FullName)
if ($LASTEXITCODE -ne 0) { $failures.Add('Python source compilation failed') }

if ($ValidateHavenPatch) {
    $scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("opendao-haven-" + [guid]::NewGuid().ToString('N'))
    try {
        git clone --quiet https://github.com/adarec1994/Haven-Tools.git $scratch
        if ($LASTEXITCODE -ne 0) { throw 'Haven Tools clone failed' }
        git -C $scratch checkout --quiet --detach 0765a5db7b5cea0cc5b405867deca7fa373921db
        if ($LASTEXITCODE -ne 0) { throw 'Haven Tools revision checkout failed' }
        git -C $scratch apply --check (Join-Path $projectRoot 'patches\haven-tools-opendao.patch')
        if ($LASTEXITCODE -ne 0) { throw 'Haven patch validation failed' }
    }
    catch { $failures.Add($_.Exception.Message) }
    finally { if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force } }
}

if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }
Write-Host 'OPENDAO_SOURCE_VALIDATION_PASS'
