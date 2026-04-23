#Requires -Version 7.0

<#
.SYNOPSIS
    Fixture-based test harness for Invoke-MetadataScan.ps1.

.DESCRIPTION
    Walks scenario directories under test-fixtures/scan/scenarios, invokes
    the scan script in -Json mode against each, and compares the emitted
    JSON to the scenario's expected.json.

    Each scenario is a self-contained fixture vault (.obsidian/ marker,
    🫥 Meta/vault-metadata.yaml, notes, expected.json). No scratch copy is
    needed — the scan script is read-only.

    Exit 0 on all-pass. Exit 1 on any mismatch, with per-scenario diffs.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scriptUnderTest = Join-Path $PSScriptRoot 'Invoke-MetadataScan.ps1'
$scenariosRoot   = Join-Path $PSScriptRoot 'test-fixtures/scan/scenarios'

if (-not (Test-Path $scriptUnderTest)) { throw "Script under test not found: $scriptUnderTest" }
if (-not (Test-Path $scenariosRoot))   { throw "Scenarios root not found: $scenariosRoot" }

function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Serializes an object to JSON with stable ordering for comparison.
    .DESCRIPTION
        Sorts top-level array entries by a deterministic key so that
        filesystem-enumeration-order differences do not produce false
        failures. Keys chosen per category:
            alias_drift  -> (note, from, to)
            shape_drift  -> (note)
            unknown_tags -> (tag)  (notes within an entry sorted too)
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Input
    )

    $normalized = [ordered]@{
        alias_drift  = @()
        shape_drift  = @()
        unknown_tags = @()
    }

    if ($Input.alias_drift) {
        $normalized.alias_drift = @($Input.alias_drift |
            Sort-Object @{Expression = { $_.note }}, @{Expression = { $_.from }}, @{Expression = { $_.to }} |
            ForEach-Object {
                [ordered]@{
                    note      = [string]$_.note
                    from      = [string]$_.from
                    to        = [string]$_.to
                    collision = [bool]$_.collision
                }
            }
        )
    }

    if ($Input.shape_drift) {
        $normalized.shape_drift = @($Input.shape_drift |
            Sort-Object @{Expression = { $_.note }} |
            ForEach-Object {
                [ordered]@{
                    note          = [string]$_.note
                    current_shape = [string]$_.current_shape
                }
            }
        )
    }

    if ($Input.unknown_tags) {
        $normalized.unknown_tags = @($Input.unknown_tags |
            Sort-Object @{Expression = { $_.tag }} |
            ForEach-Object {
                [ordered]@{
                    tag   = [string]$_.tag
                    notes = @($_.notes | Sort-Object)
                }
            }
        )
    }

    return ($normalized | ConvertTo-Json -Depth 6)
}

$scenarios = Get-ChildItem -Path $scenariosRoot -Directory | Sort-Object Name
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($scenario in $scenarios) {
    $name = $scenario.Name
    $expectedPath = Join-Path $scenario.FullName 'expected.json'

    if (-not (Test-Path $expectedPath)) {
        $failures.Add("[$name] missing expected.json")
        Write-Host "  🚨 $name (missing expected.json)" -ForegroundColor Red
        continue
    }

    # Use -OutFile so Unicode path characters round-trip through disk via
    # UTF-8, rather than stdout via the console codepage (cp1252 on Windows)
    # which corrupts surrogate-pair emoji. This matches real-world usage
    # and guards against regression of DeliberateGeek/template-obsidian#40.
    $actualOutFile = [System.IO.Path]::GetTempFileName()
    try {
        & $scriptUnderTest -VaultRoot $scenario.FullName -OutFile $actualOutFile 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
    }
    catch {
        $failures.Add("[$name] script threw: $_")
        Write-Host "  🚨 $name (script threw: $_)" -ForegroundColor Red
        if (Test-Path $actualOutFile) { Remove-Item $actualOutFile -Force }
        continue
    }

    if ($exitCode -ne 0) {
        $failures.Add("[$name] script exited with code $exitCode")
        Write-Host "  🚨 $name (exit $exitCode)" -ForegroundColor Red
        if (Test-Path $actualOutFile) { Remove-Item $actualOutFile -Force }
        continue
    }

    try {
        $actualObj = Get-Content -Path $actualOutFile -Raw -Encoding utf8 | ConvertFrom-Json
        $expectedObj = Get-Content -Path $expectedPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch {
        $failures.Add("[$name] JSON parse failed: $_")
        Write-Host "  🚨 $name (JSON parse: $_)" -ForegroundColor Red
        Remove-Item $actualOutFile -Force
        continue
    }

    Remove-Item $actualOutFile -Force

    $actualCanonical = ConvertTo-CanonicalJson -Input $actualObj
    $expectedCanonical = ConvertTo-CanonicalJson -Input $expectedObj

    if ($actualCanonical -eq $expectedCanonical) {
        Write-Host "  ✅ $name" -ForegroundColor Green
    }
    else {
        Write-Host "  🚨 $name" -ForegroundColor Red
        $failures.Add("[$name] output does not match expected")
        Write-Host "     --- expected ---" -ForegroundColor DarkGray
        $expectedCanonical -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
        Write-Host "     --- actual ---" -ForegroundColor DarkGray
        $actualCanonical -split "`n" | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
    }
}

if ($failures.Count -eq 0) {
    Write-Host ""
    Write-Host "All $($scenarios.Count) scenarios passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host ""
    Write-Host "$($failures.Count) scenario(s) failed:" -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  - $f" -ForegroundColor Red }
    exit 1
}
