#Requires -Version 7.0

<#
.SYNOPSIS
    Fixture-based test harness for Invoke-MetadataNormalize.ps1.

.DESCRIPTION
    Copies each scenario note from test-fixtures/normalize/inputs into a
    throwaway scratch vault, invokes the normalize script with the shared
    alias map, and diffs the result against test-fixtures/normalize/expected.

    Per memory-feedback 'verify_with_git_status' — this harness asserts on
    actual on-disk state, not on the script's exit code or stdout.

    Exit 0 on all-pass. Exit 1 on any mismatch, with per-scenario diffs.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot        = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptUnderTest = Join-Path $PSScriptRoot 'Invoke-MetadataNormalize.ps1'
$fixtureRoot     = Join-Path $PSScriptRoot 'test-fixtures/normalize'
$inputsDir       = Join-Path $fixtureRoot 'inputs'
$expectedDir     = Join-Path $fixtureRoot 'expected'
$aliasMap        = Join-Path $fixtureRoot 'alias-map.json'

if (-not (Test-Path $scriptUnderTest)) { throw "Script under test not found: $scriptUnderTest" }
if (-not (Test-Path $aliasMap))        { throw "Alias map not found: $aliasMap" }

$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "normalize-harness-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratchRoot '.obsidian') -Force | Out-Null

$scenarios = Get-ChildItem -Path $inputsDir -Filter '*.md' | Sort-Object Name
$failures  = [System.Collections.Generic.List[string]]::new()

foreach ($scenario in $scenarios) {
    $name         = [System.IO.Path]::GetFileNameWithoutExtension($scenario.Name)
    $scratchPath  = Join-Path $scratchRoot $scenario.Name
    $expectedPath = Join-Path $expectedDir $scenario.Name

    if (-not (Test-Path $expectedPath)) {
        $failures.Add("[$name] missing expected fixture: $expectedPath")
        continue
    }

    Copy-Item -Path $scenario.FullName -Destination $scratchPath -Force

    try {
        & $scriptUnderTest -Notes $scratchPath -AliasMapPath $aliasMap 2>&1 | Out-Null
    }
    catch {
        $failures.Add("[$name] script threw: $_")
        continue
    }

    $actualBytes   = [System.IO.File]::ReadAllBytes($scratchPath)
    $expectedBytes = [System.IO.File]::ReadAllBytes($expectedPath)

    # Compare ignoring trailing newline differences; compare the content as
    # strings so line-ending differences between fixtures and PS output do
    # not produce false failures.
    $actualText   = [System.Text.Encoding]::UTF8.GetString($actualBytes)   -replace "`r`n", "`n"
    $expectedText = [System.Text.Encoding]::UTF8.GetString($expectedBytes) -replace "`r`n", "`n"
    $actualText   = $actualText.TrimEnd("`n")
    $expectedText = $expectedText.TrimEnd("`n")

    $contentOk = ($actualText -eq $expectedText)

    if ($contentOk) {
        Write-Host "  ✅ $name" -ForegroundColor Green
    }
    else {
        Write-Host "  🚨 $name" -ForegroundColor Red
        $failures.Add("[$name] output does not match expected")
        Write-Host "     --- expected ---" -ForegroundColor DarkGray
        $expectedText -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        Write-Host "     --- actual ---" -ForegroundColor DarkGray
        $actualText -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    }
}

Remove-Item -Path $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "All $($scenarios.Count) scenarios passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "$($failures.Count) of $($scenarios.Count) scenarios failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
