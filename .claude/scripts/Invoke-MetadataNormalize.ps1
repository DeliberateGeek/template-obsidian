#Requires -Version 7.0

<#
.SYNOPSIS
    Normalizes declared alias tags to their canonical form across Obsidian notes.

.DESCRIPTION
    Reads an alias map (from JSON file or inline hashtable) and replaces
    occurrences of alias tags with their canonical equivalents in the specified
    notes' frontmatter.

    Only declared aliases are normalized silently. Fuzzy/undeclared matches
    are NOT handled by this script — those require user confirmation via the
    invoking Skill.

.PARAMETER Notes
    Comma-delimited list of note file paths (relative to vault root or absolute).

.PARAMETER AliasMapPath
    Path to a JSON file containing the alias map. The JSON should be an object
    where each key is an alias and the value is the canonical tag.
    Example: { "containers": "docker", "docker-compose": "docker", "k8s": "kubernetes" }

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataNormalize.ps1 -Notes "Knowledge/Homelab/Note.md" -AliasMapPath ".claude/temp/alias-map.json"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Notes,

    [Parameter(Mandatory)]
    [string]$AliasMapPath
)

Process {
    Assert-NotesProvided
    $aliasMap = Get-AliasMap -Path $AliasMapPath

    if ($aliasMap.Count -eq 0) {
        Write-Host "  ⚠️ Alias map is empty — nothing to normalize." -ForegroundColor Yellow
        exit 0
    }

    if ($WhatIfPreference) {
        Write-Host "  ⚠️ [WHATIF MODE] No changes will be made" -ForegroundColor Yellow
    }

    $vaultRoot = Resolve-VaultRoot -StartPath $script:notePaths[0]
    $script:totalNormalized = 0

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

    function Get-ParsedFrontmatter {
        param(
            [Parameter(Mandatory)]
            [string]$Content
        )

        if ($Content -match '^---\r?\n') {
            $firstDelimiter = [regex]::Match($Content, '^---\r?\n')
            $searchStart = $firstDelimiter.Index + $firstDelimiter.Length
            $secondDelimiter = [regex]::Match($Content.Substring($searchStart), '(?m)^---\r?\n')

            if ($secondDelimiter.Success) {
                $frontmatterEnd = $searchStart + $secondDelimiter.Index + $secondDelimiter.Length
                $frontmatterContent = $Content.Substring($firstDelimiter.Length, $searchStart + $secondDelimiter.Index - $firstDelimiter.Length)
                $body = $Content.Substring($frontmatterEnd)

                return @{
                    Frontmatter    = $frontmatterContent
                    Body           = $body
                    HasFrontmatter = $true
                }
            }
        }

        return @{
            Frontmatter    = ''
            Body           = $Content
            HasFrontmatter = $false
        }
    }

    function Get-TagsRegion {
        # Locates the `tags:` region within a frontmatter text block. Returns
        # $null if no top-level tags key exists. Otherwise returns:
        #   Shape   = 'Inline' | 'Block' | 'Scalar' | 'Empty'
        #   Tags    = string[]  (parsed tag values; empty for Empty shape)
        #   Start   = int       (character index of line start in $Frontmatter)
        #   Length  = int       (characters to remove, including trailing \n)
        param(
            [Parameter(Mandatory)]
            [string]$Frontmatter
        )

        # Match a top-level `tags:` line (no leading whitespace)
        $lineMatch = [regex]::Match($Frontmatter, '(?m)^tags\s*:[ \t]*(?<tail>.*?)(?:\r?\n|\z)')
        if (-not $lineMatch.Success) { return $null }

        $lineStart = $lineMatch.Index
        $lineEnd = $lineStart + $lineMatch.Length
        $tail = $lineMatch.Groups['tail'].Value.Trim()

        # Inline array
        if ($tail -match '^\[(?<inner>.*)\]\s*$') {
            $inner = $Matches['inner'].Trim()
            $tags = if ($inner -eq '') {
                @()
            }
            else {
                $inner -split ',' | ForEach-Object { $_.Trim().Trim('"',"'") } | Where-Object { $_ -ne '' }
            }
            $shape = if ($tags.Count -eq 0) { 'Empty' } else { 'Inline' }
            return @{
                Shape  = $shape
                Tags   = [string[]]$tags
                Start  = $lineStart
                Length = $lineEnd - $lineStart
            }
        }

        # Block list: consume following `  - value` lines
        if ($tail -eq '') {
            $tags = [System.Collections.Generic.List[string]]::new()
            $cursor = $lineEnd
            $len = $Frontmatter.Length
            while ($cursor -lt $len) {
                $nextNewline = $Frontmatter.IndexOf("`n", $cursor)
                if ($nextNewline -lt 0) { $nextNewline = $len - 1 }
                $line = $Frontmatter.Substring($cursor, $nextNewline - $cursor + 1)
                $trimmed = $line.TrimEnd("`r","`n")
                if ($trimmed -match '^\s+-\s+(?<val>.+?)\s*$') {
                    $tags.Add($Matches['val'].Trim('"',"'"))
                    $cursor = $nextNewline + 1
                    continue
                }
                if ($trimmed -match '^\s*$') {
                    # Blank line ends the block
                    break
                }
                # Next top-level key or non-continuation content
                break
            }
            $shape = if ($tags.Count -eq 0) { 'Empty' } else { 'Block' }
            return @{
                Shape  = $shape
                Tags   = [string[]]$tags
                Start  = $lineStart
                Length = $cursor - $lineStart
            }
        }

        # Scalar form: tags: single-value
        return @{
            Shape  = 'Scalar'
            Tags   = [string[]]@($tail.Trim('"',"'"))
            Start  = $lineStart
            Length = $lineEnd - $lineStart
        }
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

    function ConvertTo-InlineTagsLine {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Tags
        )

        if ($Tags.Count -eq 0) { return 'tags: []' }
        return 'tags: [' + ($Tags -join ', ') + ']'
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
}

End {}
