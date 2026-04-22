#Requires -Version 7.0

<#
.SYNOPSIS
    Normalizes declared alias tags to their canonical form, or rewrites tag
    region shape to inline, across Obsidian notes.

.DESCRIPTION
    Two modes, selected by parameter set:

    - Alias mode (default): reads an alias map and replaces occurrences of
      alias tags with their canonical equivalents in the specified notes'
      frontmatter. Only declared aliases are normalized silently. Fuzzy or
      undeclared matches are NOT handled — those require user confirmation
      via the invoking Skill.

    - ShapeOnly mode (-ShapeOnly): rewrites each note's tags region to inline
      shape (`tags: [a, b, c]`), preserving the existing tag set. No alias
      substitution. Notes already in inline shape are skipped.

.PARAMETER Notes
    Comma-delimited list of note file paths (relative to vault root or absolute).

.PARAMETER AliasMapPath
    Path to a JSON file containing the alias map. The JSON should be an object
    where each key is an alias and the value is the canonical tag.
    Example: { "containers": "docker", "docker-compose": "docker", "k8s": "kubernetes" }

.PARAMETER ShapeOnly
    Switch — when set, normalize tags region shape only (no alias substitution).
    Mutually exclusive with -AliasMapPath.

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataNormalize.ps1 -Notes "Knowledge/Homelab/Note.md" -AliasMapPath ".claude/temp/alias-map.json"

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataNormalize.ps1 -Notes "Knowledge/Block-Shaped.md,Knowledge/Scalar-Shaped.md" -ShapeOnly
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Alias')]
param(
    [Parameter(Mandatory)]
    [string]$Notes,

    [Parameter(Mandatory, ParameterSetName = 'Alias')]
    [string]$AliasMapPath,

    [Parameter(Mandatory, ParameterSetName = 'ShapeOnly')]
    [switch]$ShapeOnly
)

Process {
    Assert-NotesProvided

    if ($WhatIfPreference) {
        Write-Host "  ⚠️ [WHATIF MODE] No changes will be made" -ForegroundColor Yellow
    }

    $vaultRoot = Resolve-VaultRoot -StartPath $script:notePaths[0]
    $script:totalNormalized = 0

    if ($PSCmdlet.ParameterSetName -eq 'ShapeOnly') {
        foreach ($notePath in $script:notePaths) {
            $resolvedPath = Resolve-NotePath -NotePath $notePath
            Assert-NoteExists -Path $resolvedPath
            Invoke-ShapeOnlyNote -Path $resolvedPath -VaultRoot $vaultRoot
        }

        if ($script:totalNormalized -eq 0) {
            Write-Host "  ℹ️ No shape drift found to normalize." -ForegroundColor DarkGray
        }
        return
    }

    $aliasMap = Get-AliasMap -Path $AliasMapPath

    if ($aliasMap.Count -eq 0) {
        Write-Host "  ⚠️ Alias map is empty — nothing to normalize." -ForegroundColor Yellow
        exit 0
    }

    foreach ($notePath in $script:notePaths) {
        $resolvedPath = Resolve-NotePath -NotePath $notePath
        Assert-NoteExists -Path $resolvedPath
        Invoke-NormalizeNote -Path $resolvedPath -AliasMap $aliasMap -VaultRoot $vaultRoot
    }

    if ($script:totalNormalized -eq 0) {
        Write-Host "  ℹ️ No alias tags found to normalize." -ForegroundColor DarkGray
    }
}

Begin {
    $ErrorActionPreference = 'Stop'

    Import-Module (Join-Path $PSScriptRoot 'MetadataParsing.psm1') -Force

    # --- Parse note paths ---
    # Force array context — a single-element pipeline result would otherwise
    # collapse to a scalar string, and `$script:notePaths[0]` would index
    # the first character instead of the first path. That misrouted
    # Resolve-VaultRoot to cwd-adjacent `.obsidian/` folders.
    $script:notePaths = @(
        $Notes -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
    $script:totalNormalized = 0

    # =========================================================================
    # Helper Functions
    # =========================================================================

    function Assert-NotesProvided {
        if ($script:notePaths.Count -eq 0) {
            Write-Host "  🚨 No note paths provided." -ForegroundColor Red
            exit 1
        }
    }

    function Assert-NoteExists {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if (-not (Test-Path $Path)) {
            Write-Host "  🚨 Note not found: $Path" -ForegroundColor Red
            exit 1
        }
    }

    function Resolve-NotePath {
        param(
            [Parameter(Mandatory)]
            [string]$NotePath
        )

        if ([System.IO.Path]::IsPathRooted($NotePath)) {
            return $NotePath
        }
        return Join-Path (Get-Location) $NotePath
    }

    function Resolve-VaultRoot {
        param(
            [Parameter(Mandatory)]
            [string]$StartPath
        )

        $resolvedStart = Resolve-NotePath -NotePath $StartPath
        $dir = if (Test-Path $resolvedStart -PathType Container) {
            $resolvedStart
        }
        else {
            Split-Path $resolvedStart -Parent
        }

        while ($dir) {
            if (Test-Path (Join-Path $dir '.obsidian')) {
                return $dir
            }
            $parent = Split-Path $dir -Parent
            if ($parent -eq $dir) { break }
            $dir = $parent
        }

        Write-Host "  🚨 Could not find vault root (.obsidian/) from path: $resolvedStart" -ForegroundColor Red
        exit 1
    }

    function Get-AliasMap {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        $resolvedPath = Resolve-NotePath -NotePath $Path
        if (-not (Test-Path $resolvedPath)) {
            Write-Host "  🚨 Alias map file not found: $resolvedPath" -ForegroundColor Red
            exit 1
        }

        try {
            $map = Get-Content $resolvedPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Host "  🚨 Invalid JSON in alias map: $_" -ForegroundColor Red
            exit 1
        }

        return $map
    }

    function Resolve-NormalizedTagSet {
        # Given input tags and an alias map, produces an ordered, deduped
        # result preserving first-seen order. Reports which substitutions
        # and collisions occurred.
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Tags,

            [Parameter(Mandatory)]
            [hashtable]$AliasMap
        )

        $result = [System.Collections.Generic.List[string]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $substitutions = [System.Collections.Generic.List[pscustomobject]]::new()
        $collisions = [System.Collections.Generic.List[pscustomobject]]::new()

        # Pre-compute the set of literal (non-alias) tags present in the
        # input. An alias -> canonical substitution where the canonical also
        # appears literally in the input is a collision regardless of order,
        # so the audit log categorizes it as NORMALIZE+DEDUPE even when the
        # alias is encountered before the canonical.
        $literalTags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($t in $Tags) {
            if (-not $AliasMap.ContainsKey($t)) { [void]$literalTags.Add($t) }
        }

        foreach ($tag in $Tags) {
            if ($AliasMap.ContainsKey($tag)) {
                $canonical = [string]$AliasMap[$tag]
                $isCollision = $seen.Contains($canonical) -or $literalTags.Contains($canonical)
                if ($isCollision) {
                    $collisions.Add([pscustomobject]@{ Alias = $tag; Canonical = $canonical })
                    if (-not $seen.Contains($canonical)) {
                        [void]$seen.Add($canonical)
                        $result.Add($canonical)
                    }
                    continue
                }
                $substitutions.Add([pscustomobject]@{ Alias = $tag; Canonical = $canonical })
                [void]$seen.Add($canonical)
                $result.Add($canonical)
            }
            else {
                if ($seen.Contains($tag)) { continue }
                [void]$seen.Add($tag)
                $result.Add($tag)
            }
        }

        return [pscustomobject]@{
            Tags          = [string[]]$result
            Substitutions = $substitutions
            Collisions    = $collisions
        }
    }

    function Invoke-NormalizeNote {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [hashtable]$AliasMap,

            [Parameter(Mandatory)]
            [string]$VaultRoot
        )

        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $parsed = Get-ParsedFrontmatter -Content $content

        if (-not $parsed.HasFrontmatter) {
            return
        }

        $frontmatter = $parsed.Frontmatter
        $region = Get-TagsRegion -Frontmatter $frontmatter

        if (-not $region) { return }
        if ($region.Tags.Count -eq 0) { return }

        # Gate: only touch notes where at least one tag is a declared alias.
        # Notes with block-shape tags but no alias drift stay block-shape —
        # shape sweeping is out of scope (see template-obsidian#24).
        $hasAlias = $false
        foreach ($t in $region.Tags) {
            if ($AliasMap.ContainsKey($t)) { $hasAlias = $true; break }
        }
        if (-not $hasAlias) { return }

        $resolved = Resolve-NormalizedTagSet -Tags $region.Tags -AliasMap $AliasMap

        # Collisions resolved via dedupe are logged as NORMALIZE+DEDUPE.
        # Pure substitutions are logged as NORMALIZE.
        $normalizations = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $resolved.Substitutions) {
            $normalizations.Add("$($s.Alias) -> $($s.Canonical)")
        }
        foreach ($c in $resolved.Collisions) {
            $normalizations.Add("$($c.Alias) -> $($c.Canonical) [deduped]")
        }

        if ($normalizations.Count -eq 0) { return }

        $newTagsLine = (ConvertTo-InlineTagsLine -Tags $resolved.Tags) + "`n"
        $newFrontmatter = $frontmatter.Substring(0, $region.Start) + $newTagsLine + $frontmatter.Substring($region.Start + $region.Length)

        $relativePath = $Path.Replace($VaultRoot, '').TrimStart('\', '/')
        $normalizationList = $normalizations -join ', '

        if ($PSCmdlet.ShouldProcess($relativePath, "Normalize tags: $normalizationList")) {
            $newContent = "---`n$newFrontmatter---`n$($parsed.Body)"
            Set-Content -Path $Path -Value $newContent -NoNewline -Encoding utf8NoBOM

            $script:totalNormalized += $resolved.Substitutions.Count + $resolved.Collisions.Count
        }
    }

    function Invoke-ShapeOnlyNote {
        # Rewrite a note's tags region to inline shape, preserving the tag
        # set. Skip notes whose tags region is already Inline or absent.
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$VaultRoot
        )

        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $parsed = Get-ParsedFrontmatter -Content $content

        if (-not $parsed.HasFrontmatter) { return }

        $frontmatter = $parsed.Frontmatter
        $region = Get-TagsRegion -Frontmatter $frontmatter

        if (-not $region) { return }
        if ($region.Tags.Count -eq 0) { return }
        if ($region.Shape -eq 'Inline') { return }

        $newTagsLine = (ConvertTo-InlineTagsLine -Tags $region.Tags) + "`n"
        $newFrontmatter = $frontmatter.Substring(0, $region.Start) + $newTagsLine + $frontmatter.Substring($region.Start + $region.Length)

        $relativePath = $Path.Replace($VaultRoot, '').TrimStart('\', '/')
        $previousShape = $region.Shape.ToLowerInvariant()

        if ($PSCmdlet.ShouldProcess($relativePath, "Normalize shape: $previousShape -> inline ($($region.Tags.Count) tags preserved)")) {
            $newContent = "---`n$newFrontmatter---`n$($parsed.Body)"
            Set-Content -Path $Path -Value $newContent -NoNewline -Encoding utf8NoBOM

            $script:totalNormalized += 1
        }
    }
}

End {}
