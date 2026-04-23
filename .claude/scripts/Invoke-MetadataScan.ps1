#Requires -Version 7.0

<#
.SYNOPSIS
    Scans an Obsidian vault's notes and emits structured metadata-drift findings.

.DESCRIPTION
    Consumed exclusively by the /metadata-check Skill
    (DeliberateGeek/template-obsidian#27). Walks vault notes, classifies
    frontmatter tags against the canonical list in vault-metadata.yaml, and
    emits findings in three categories:

        - alias_drift : notes using declared-alias tags (should normalize)
        - shape_drift : tags frontmatter not in inline-array shape
        - unknown_tags: tags not canonical and not declared-alias

    Explicitly out of scope for v1:
        - Fuzzy synonym detection
        - Retirement / promotion candidate logic
        - Staleness detection
        - Property integrity checks
        - Body-inline #tag extraction (frontmatter-only)

    Exit codes:
        0 - Scan ran; findings emitted
        2 - Environment error (missing vault-metadata.yaml, YAML module, etc.)

    Prerequisites:
        - PowerShell 7+
        - powershell-yaml module

.PARAMETER VaultRoot
    Path to the vault root (directory containing .obsidian/). Required.

.PARAMETER Json
    Emit findings as JSON to stdout. Default is human-readable text.
    NOTE: stdout encoding follows the current console codepage. On Windows
    (cp1252) this corrupts surrogate-pair emoji characters (e.g., 📚 U+1F4DA)
    in paths. For vaults with emoji folder names, use -OutFile instead.

.PARAMETER OutFile
    Write JSON findings to a UTF-8 file (no BOM) at this path via
    [System.IO.File]::WriteAllText, bypassing the console codepage. This
    is the correct flag for programmatic consumption when vault paths
    contain emoji or other non-BMP characters. Mutually exclusive with -Json.

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataScan.ps1 -VaultRoot .

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataScan.ps1 -VaultRoot . -Json

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataScan.ps1 -VaultRoot . -OutFile scan.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$VaultRoot,

    [Parameter()]
    [switch]$Json,

    [Parameter()]
    [string]$OutFile
)

Process {
    $canonical = Read-CanonicalLists -MetadataPath $script:resolvedMetadataPath

    $findings = [ordered]@{
        alias_drift   = [System.Collections.Generic.List[object]]::new()
        shape_drift   = [System.Collections.Generic.List[object]]::new()
        unknown_tags  = @{}  # tag -> List[string] (note paths)
    }

    $notes = Get-VaultNotes -VaultRoot $script:resolvedVaultRoot

    foreach ($note in $notes) {
        Test-Note -NotePath $note -VaultRoot $script:resolvedVaultRoot -Canonical $canonical -Findings $findings
    }

    # Collapse unknown_tags hashtable into ordered list-of-objects for JSON output.
    $unknownList = [System.Collections.Generic.List[object]]::new()
    foreach ($tag in ($findings.unknown_tags.Keys | Sort-Object)) {
        $unknownList.Add([pscustomobject]@{
            tag   = $tag
            notes = [string[]]$findings.unknown_tags[$tag]
        })
    }

    $output = [ordered]@{
        alias_drift  = $findings.alias_drift
        shape_drift  = $findings.shape_drift
        unknown_tags = $unknownList
    }

    if ($OutFile) {
        Write-UnicodeSafeJson -Output $output -Path $OutFile
    }
    elseif ($Json) {
        Write-Output ($output | ConvertTo-Json -Depth 6)
    }
    else {
        Write-HumanOutput -Output $output
    }

    exit 0
}

Begin {
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'MetadataParsing.psm1') -Force

    # =========================================================================
    # Helper Functions
    # =========================================================================

    function Exit-Environment {
        param(
            [Parameter(Mandatory)]
            [string]$Message
        )
        Write-Host "  🚨 $Message" -ForegroundColor Red
        exit 2
    }

    function Assert-YamlModule {
        if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
            Exit-Environment -Message @"
powershell-yaml module is not installed.
Install it once per machine:

    Install-Module -Name powershell-yaml -Scope CurrentUser -Force
"@
        }
        Import-Module powershell-yaml -ErrorAction Stop
    }

    function Resolve-InputPath {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )
        if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
        return (Join-Path (Get-Location) $Path)
    }

    function Read-CanonicalLists {
        <#
        .SYNOPSIS
            Parses vault-metadata.yaml and returns lookup sets for tag classification.
        .OUTPUTS
            Hashtable:
                CanonicalTags = HashSet[string] (topic ids + also_tag content types)
                AliasMap      = Hashtable alias -> canonical id
        #>
        param(
            [Parameter(Mandatory)]
            [string]$MetadataPath
        )

        try {
            $content = Get-Content -Path $MetadataPath -Raw -Encoding utf8
            $metadata = ConvertFrom-Yaml -Yaml $content
        }
        catch {
            Exit-Environment -Message "Could not parse vault-metadata.yaml: $_"
        }

        $canonicalTags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $aliasMap = @{}

        # Topic ids and their aliases
        if ($metadata.ContainsKey('topics') -and $metadata['topics']) {
            foreach ($topic in $metadata['topics']) {
                if ($null -eq $topic) { continue }
                if (-not $topic.ContainsKey('id')) { continue }
                $id = [string]$topic['id']
                if ([string]::IsNullOrWhiteSpace($id)) { continue }
                [void]$canonicalTags.Add($id)

                if ($topic.ContainsKey('aliases') -and $topic['aliases']) {
                    foreach ($alias in $topic['aliases']) {
                        $aliasStr = [string]$alias
                        if (-not [string]::IsNullOrWhiteSpace($aliasStr)) {
                            $aliasMap[$aliasStr] = $id
                        }
                    }
                }
            }
        }

        # Content type ids with also_tag: true
        if ($metadata.ContainsKey('content_types') -and $metadata['content_types']) {
            foreach ($ct in $metadata['content_types']) {
                if ($null -eq $ct) { continue }
                if (-not $ct.ContainsKey('id')) { continue }
                if ($ct.ContainsKey('also_tag') -and $ct['also_tag'] -eq $true) {
                    [void]$canonicalTags.Add([string]$ct['id'])
                }
            }
        }

        return @{
            CanonicalTags = $canonicalTags
            AliasMap      = $aliasMap
        }
    }

    function Get-VaultNotes {
        <#
        .SYNOPSIS
            Enumerates markdown files under the vault root, excluding infrastructure folders.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$VaultRoot
        )

        # Exclusion patterns are matched against path segments.
        # .claude and .obsidian are dev-infra dot-folders Obsidian itself hides.
        # The 🫥 emoji prefix is the vault-wide convention for metadata/auxiliary
        # folders (per vault-guide.md); any segment starting with '🫥 ' is
        # infrastructure and excluded from content scanning. This covers
        # 🫥 Meta, 🫥 Attachments, 🫥 Templates, 🫥 Templater, and any future
        # 🫥-prefixed folder including compound-emoji variants like
        # "🫥 📂 Attachments".
        $excludedLiteralSegments = @('.claude', '.obsidian')
        $infraFolderPrefix = '🫥 '

        $files = Get-ChildItem -Path $VaultRoot -Recurse -File -Filter '*.md' -Force
        $results = [System.Collections.Generic.List[string]]::new()

        foreach ($file in $files) {
            $relative = $file.FullName.Substring($VaultRoot.Length).TrimStart('\', '/')
            $segments = $relative -split '[\\/]'
            $excluded = $false
            foreach ($seg in $segments) {
                if ($excludedLiteralSegments -contains $seg) { $excluded = $true; break }
                if ($seg.StartsWith($infraFolderPrefix)) { $excluded = $true; break }
            }
            if (-not $excluded) {
                $results.Add($file.FullName)
            }
        }

        return $results
    }

    function Test-Note {
        param(
            [Parameter(Mandatory)]
            [string]$NotePath,

            [Parameter(Mandatory)]
            [string]$VaultRoot,

            [Parameter(Mandatory)]
            [hashtable]$Canonical,

            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Findings
        )

        $content = Get-Content -Path $NotePath -Raw -Encoding utf8
        $parsed = Get-ParsedFrontmatter -Content $content
        if (-not $parsed.HasFrontmatter) { return }

        $region = Get-TagsRegion -Frontmatter $parsed.Frontmatter
        if (-not $region) { return }
        if ($region.Tags.Count -eq 0) { return }

        $relative = $NotePath.Substring($VaultRoot.Length).TrimStart('\', '/').Replace('\', '/')

        # Shape drift: anything not Inline is drift (Block, Scalar).
        if ($region.Shape -ne 'Inline') {
            $Findings.shape_drift.Add([pscustomobject]@{
                note          = $relative
                current_shape = $region.Shape.ToLowerInvariant()
            })
        }

        $canonicalTags = $Canonical.CanonicalTags
        $aliasMap = $Canonical.AliasMap
        $literalSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($t in $region.Tags) {
            if (-not $aliasMap.ContainsKey($t)) { [void]$literalSet.Add($t) }
        }

        foreach ($tag in $region.Tags) {
            if ($aliasMap.ContainsKey($tag)) {
                $canonicalId = $aliasMap[$tag]
                $collision = $literalSet.Contains($canonicalId)
                $Findings.alias_drift.Add([pscustomobject]@{
                    note      = $relative
                    from      = $tag
                    to        = $canonicalId
                    collision = [bool]$collision
                })
                continue
            }
            if ($canonicalTags.Contains($tag)) { continue }

            if (-not $Findings.unknown_tags.ContainsKey($tag)) {
                $Findings.unknown_tags[$tag] = [System.Collections.Generic.List[string]]::new()
            }
            if (-not $Findings.unknown_tags[$tag].Contains($relative)) {
                $Findings.unknown_tags[$tag].Add($relative)
            }
        }
    }

    function Write-UnicodeSafeJson {
        <#
        .SYNOPSIS
            Serializes findings to JSON and writes via WriteAllText so
            surrogate-pair emoji characters round-trip correctly. Bypasses
            PowerShell's console-codepage output path.
        #>
        param(
            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Output,

            [Parameter(Mandatory)]
            [string]$Path
        )

        $json = $Output | ConvertTo-Json -Depth 6
        $resolved = [System.IO.Path]::GetFullPath($Path)
        $dir = [System.IO.Path]::GetDirectoryName($resolved)
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Path $dir -Force
        }
        [System.IO.File]::WriteAllText($resolved, $json, [System.Text.UTF8Encoding]::new($false))
    }

    function Write-HumanOutput {
        param(
            [Parameter(Mandatory)]
            [System.Collections.IDictionary]$Output
        )

        $aliasCount = $Output.alias_drift.Count
        $shapeCount = $Output.shape_drift.Count
        $unknownCount = $Output.unknown_tags.Count

        if ($aliasCount -eq 0 -and $shapeCount -eq 0 -and $unknownCount -eq 0) {
            Write-Host "  ✅ No findings. Vault metadata is in canonical shape." -ForegroundColor Green
            return
        }

        Write-Host ""
        Write-Host "Metadata scan findings:" -ForegroundColor Cyan

        if ($aliasCount -gt 0) {
            Write-Host ""
            Write-Host "  Alias drift ($aliasCount):" -ForegroundColor Yellow
            foreach ($f in $Output.alias_drift) {
                $suffix = if ($f.collision) { ' [collision — will dedupe]' } else { '' }
                Write-Host "    $($f.note): $($f.from) -> $($f.to)$suffix"
            }
        }

        if ($shapeCount -gt 0) {
            Write-Host ""
            Write-Host "  Shape drift ($shapeCount):" -ForegroundColor Yellow
            foreach ($f in $Output.shape_drift) {
                Write-Host "    $($f.note) [current: $($f.current_shape)]"
            }
        }

        if ($unknownCount -gt 0) {
            Write-Host ""
            Write-Host "  Unknown tags ($unknownCount):" -ForegroundColor Yellow
            foreach ($f in $Output.unknown_tags) {
                Write-Host "    $($f.tag) ($($f.notes.Count) note(s)):"
                foreach ($n in $f.notes) {
                    Write-Host "      - $n"
                }
            }
        }
    }

    # =========================================================================
    # Entry setup
    # =========================================================================

    Assert-YamlModule

    $script:resolvedVaultRoot = Resolve-InputPath -Path $VaultRoot
    if (-not (Test-Path $script:resolvedVaultRoot -PathType Container)) {
        Exit-Environment -Message "VaultRoot is not a directory: $script:resolvedVaultRoot"
    }
    if (-not (Test-Path (Join-Path $script:resolvedVaultRoot '.obsidian'))) {
        Exit-Environment -Message "VaultRoot does not contain .obsidian/: $script:resolvedVaultRoot"
    }

    $script:resolvedMetadataPath = Join-Path $script:resolvedVaultRoot '🫥 Meta' 'vault-metadata.yaml'
    if (-not (Test-Path $script:resolvedMetadataPath)) {
        Exit-Environment -Message "vault-metadata.yaml not found at: $script:resolvedMetadataPath"
    }
}

End {}
