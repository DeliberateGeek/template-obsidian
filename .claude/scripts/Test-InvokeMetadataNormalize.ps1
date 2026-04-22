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

$scriptUnderTest = Join-Path $PSScriptRoot 'Invoke-MetadataNormalize.ps1'
$fixtureRoot     = Join-Path $PSScriptRoot 'test-fixtures/normalize'
$aliasMap        = Join-Path $fixtureRoot 'alias-map.json'

if (-not (Test-Path $scriptUnderTest)) { throw "Script under test not found: $scriptUnderTest" }
if (-not (Test-Path $aliasMap))        { throw "Alias map not found: $aliasMap" }

$scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) "normalize-harness-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $scratchRoot '.obsidian') -Force | Out-Null

$failures      = [System.Collections.Generic.List[string]]::new()
$totalScenario = 0

function Invoke-Suite {
    param(
        [Parameter(Mandatory)] [string]$SuiteName,
        [Parameter(Mandatory)] [string]$InputsDir,
        [Parameter(Mandatory)] [string]$ExpectedDir,
        [Parameter(Mandatory)] [ValidateSet('Alias', 'ShapeOnly')] [string]$Mode
    )

    $scenarios = Get-ChildItem -Path $InputsDir -Filter '*.md' | Sort-Object Name
    Write-Host ""
    Write-Host "=== $SuiteName ($($scenarios.Count) scenarios) ===" -ForegroundColor Cyan

    foreach ($scenario in $scenarios) {
        $script:totalScenario++
        $name         = [System.IO.Path]::GetFileNameWithoutExtension($scenario.Name)
        $label        = "$SuiteName/$name"
        $scratchPath  = Join-Path $scratchRoot "$SuiteName-$($scenario.Name)"
        $expectedPath = Join-Path $ExpectedDir $scenario.Name

        if (-not (Test-Path $expectedPath)) {
            $script:failures.Add("[$label] missing expected fixture: $expectedPath")
            continue
        }

        Copy-Item -Path $scenario.FullName -Destination $scratchPath -Force

        try {
            if ($Mode -eq 'Alias') {
                & $scriptUnderTest -Notes $scratchPath -AliasMapPath $aliasMap 2>&1 | Out-Null
            }
            else {
                & $scriptUnderTest -Notes $scratchPath -ShapeOnly 2>&1 | Out-Null
            }
        }
        catch {
            $script:failures.Add("[$label] script threw: $_")
            continue
        }

        $actualBytes   = [System.IO.File]::ReadAllBytes($scratchPath)
        $expectedBytes = [System.IO.File]::ReadAllBytes($expectedPath)

        $actualText   = [System.Text.Encoding]::UTF8.GetString($actualBytes)   -replace "`r`n", "`n"
        $expectedText = [System.Text.Encoding]::UTF8.GetString($expectedBytes) -replace "`r`n", "`n"
        $actualText   = $actualText.TrimEnd("`n")
        $expectedText = $expectedText.TrimEnd("`n")

        if ($actualText -eq $expectedText) {
            Write-Host "  ✅ $name" -ForegroundColor Green
        }
        else {
            Write-Host "  🚨 $name" -ForegroundColor Red
            $script:failures.Add("[$label] output does not match expected")
            Write-Host "     --- expected ---" -ForegroundColor DarkGray
            $expectedText -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
            Write-Host "     --- actual ---" -ForegroundColor DarkGray
            $actualText -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        }
    }
}

Invoke-Suite -SuiteName 'alias' `
    -InputsDir   (Join-Path $fixtureRoot 'inputs') `
    -ExpectedDir (Join-Path $fixtureRoot 'expected') `
    -Mode        'Alias'

Invoke-Suite -SuiteName 'shape-only' `
    -InputsDir   (Join-Path $fixtureRoot 'shape-only/inputs') `
    -ExpectedDir (Join-Path $fixtureRoot 'shape-only/expected') `
    -Mode        'ShapeOnly'

Remove-Item -Path $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($failures.Count -eq 0) {
    Write-Host "All $totalScenario scenarios passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "$($failures.Count) of $totalScenario scenarios failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
