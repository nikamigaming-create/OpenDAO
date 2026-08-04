[CmdletBinding()]
param()

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

if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }
Write-Host 'OPENDAO_SOURCE_VALIDATION_PASS'
