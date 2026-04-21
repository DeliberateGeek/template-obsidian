#Requires -Version 7.0

<#
.SYNOPSIS
    Normalizes declared alias tags to their canonical form across Obsidian notes.

.DESCRIPTION
    Reads an alias map (from JSON file or inline hashtable) and replaces
    occurrences of alias tags with their canonical equivalents in the specified
    notes' frontmatter. Appends an audit log entry for each normalization.

    Only declared aliases are normalized silently. Fuzzy/undeclared matches
    are NOT handled by this script — those require user confirmation via the
    /audit-metadata Skill.

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
    $auditLogDir = Resolve-AuditLogDirectory -VaultRoot $vaultRoot
    $script:totalNormalized = 0

    foreach ($notePath in $script:notePaths) {
        $resolvedPath = Resolve-NotePath -NotePath $notePath
        Assert-NoteExists -Path $resolvedPath
        Invoke-NormalizeNote -Path $resolvedPath -AliasMap $aliasMap -VaultRoot $vaultRoot -AuditLogDir $auditLogDir
    }

    if ($script:totalNormalized -eq 0) {
        Write-Host "  ℹ️ No alias tags found to normalize." -ForegroundColor DarkGray
    }
}

Begin {
    $ErrorActionPreference = 'Stop'

    # --- Parse note paths ---
    $script:notePaths = $Notes -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }
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

    function Resolve-AuditLogDirectory {
        param(
            [Parameter(Mandatory)]
            [string]$VaultRoot
        )

        $metaDir = Get-ChildItem -Path $VaultRoot -Directory |
            Where-Object { $_.Name -match 'Meta$' } |
            Select-Object -First 1

        if ($metaDir) {
            return Join-Path $metaDir.FullName 'Audit Logs'
        }

        return Join-Path $VaultRoot 'Meta' 'Audit Logs'
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

    function Write-AuditEntry {
        param(
            [Parameter(Mandatory)]
            [string]$LogDir,

            [Parameter(Mandatory)]
            [string]$Message
        )

        if (-not (Test-Path $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
        }

        $logFile = Join-Path $LogDir "$(Get-Date -Format 'yyyy-MM-dd').md"
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $entry = "- ``$timestamp`` $Message"

        if (Test-Path $logFile) {
            Add-Content -Path $logFile -Value $entry -Encoding utf8NoBOM
        }
        else {
            $header = "# Metadata Audit Log $(Get-Date -Format 'yyyy-MM-dd')`n`n$entry"
            Set-Content -Path $logFile -Value $header -Encoding utf8NoBOM
        }
    }

    function Invoke-NormalizeNote {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [hashtable]$AliasMap,

            [Parameter(Mandatory)]
            [string]$VaultRoot,

            [Parameter(Mandatory)]
            [string]$AuditLogDir
        )

        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $parsed = Get-ParsedFrontmatter -Content $content

        if (-not $parsed.HasFrontmatter) {
            return
        }

        # Extract tags from frontmatter (handles both YAML list and inline formats)
        $frontmatter = $parsed.Frontmatter
        $changed = $false
        $normalizations = [System.Collections.Generic.List[string]]::new()

        foreach ($alias in $AliasMap.Keys) {
            $canonical = $AliasMap[$alias]

            # Each pattern pairs with a replacement string keyed to its capture
            # shape. The block-list pattern has two capture groups (leading
            # whitespace + trailing whitespace); the inline-array pattern uses
            # lookaround assertions and has no capture groups. Using a shared
            # replacement string like "`${1}$canonical`${2}" against the inline
            # pattern would leak literal ${1}/${2} into the output because
            # those backreferences do not resolve. See TO#18 for the bug that
            # motivated the split.
            $tagPatternReplacements = @(
                @{
                    Pattern     = "(?m)^(\s*-\s+)$([regex]::Escape($alias))(\s*)$"
                    Replacement = "`${1}$canonical`${2}"
                },
                @{
                    Pattern     = "(?<=\btags:\s*\[.*?)$([regex]::Escape($alias))(?=.*?\])"
                    Replacement = $canonical
                }
            )

            foreach ($entry in $tagPatternReplacements) {
                if ($frontmatter -match $entry.Pattern) {
                    $frontmatter = $frontmatter -replace $entry.Pattern, $entry.Replacement
                    $changed = $true
                    $normalizations.Add("$alias -> $canonical")
                }
            }
        }

        if (-not $changed) {
            return
        }

        $relativePath = $Path.Replace($VaultRoot, '').TrimStart('\', '/')
        $normalizationList = $normalizations -join ', '

        if ($PSCmdlet.ShouldProcess($relativePath, "Normalize tags: $normalizationList")) {
            $newContent = "---`n$frontmatter---`n$($parsed.Body)"
            Set-Content -Path $Path -Value $newContent -NoNewline -Encoding utf8NoBOM

            foreach ($normalization in $normalizations) {
                Write-AuditEntry -LogDir $AuditLogDir -Message "NORMALIZE: ``$relativePath`` tag $normalization"
            }

            $script:totalNormalized += $normalizations.Count
        }
    }
}

End {}
