#Requires -Version 7.0

<#
.SYNOPSIS
    Stamps notes with metadata_review: pending for deferred classification.

.DESCRIPTION
    Adds or updates the metadata_review frontmatter field on one or more
    Obsidian notes. Used during capture when the user wants to defer
    metadata classification to a later session-end or audit pass.

    Appends an audit log entry for each note processed. Silent on success;
    exits nonzero with stderr on failure.

.PARAMETER Notes
    Comma-delimited list of note file paths (relative to vault root or absolute).

.PARAMETER Reason
    Optional reason for deferral. Stored in the metadata_review_note
    frontmatter field.

.EXAMPLE
    pwsh.exe -File .claude/scripts/Set-MetadataDefer.ps1 -Notes "Inbox/Quick thought.md"

.EXAMPLE
    pwsh.exe -File .claude/scripts/Set-MetadataDefer.ps1 -Notes "Inbox/Note1.md,Inbox/Note2.md" -Reason "classify during next audit"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Notes,

    [string]$Reason
)

Process {
    Assert-NotesProvided

    if ($WhatIfPreference) {
        Write-Host "  ⚠️ [WHATIF MODE] No changes will be made" -ForegroundColor Yellow
    }

    $vaultRoot = Resolve-VaultRoot -StartPath $script:notePaths[0]
    $auditLogDir = Resolve-AuditLogDirectory -VaultRoot $vaultRoot

    foreach ($notePath in $script:notePaths) {
        $resolvedPath = Resolve-NotePath -NotePath $notePath
        Assert-NoteExists -Path $resolvedPath
        Set-DeferFlag -Path $resolvedPath -VaultRoot $vaultRoot -AuditLogDir $auditLogDir
    }
}

Begin {
    $ErrorActionPreference = 'Stop'

    # --- Parse note paths ---
    $script:notePaths = $Notes -split ',' |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne '' }

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

        # Find the Meta folder (may have emoji prefix)
        $metaDir = Get-ChildItem -Path $VaultRoot -Directory |
            Where-Object { $_.Name -match 'Meta$' } |
            Select-Object -First 1

        if ($metaDir) {
            return Join-Path $metaDir.FullName 'Audit Logs'
        }

        return Join-Path $VaultRoot 'Meta' 'Audit Logs'
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

    function Set-FrontmatterField {
        param(
            [Parameter(Mandatory)]
            [string]$Frontmatter,

            [Parameter(Mandatory)]
            [string]$Field,

            [Parameter(Mandatory)]
            [string]$Value
        )

        $pattern = "(?m)^${Field}:.*$"
        if ($Frontmatter -match $pattern) {
            return $Frontmatter -replace $pattern, "${Field}: ${Value}"
        }

        return $Frontmatter.TrimEnd("`r", "`n") + "`n${Field}: ${Value}`n"
    }

    function Remove-FrontmatterField {
        param(
            [Parameter(Mandatory)]
            [string]$Frontmatter,

            [Parameter(Mandatory)]
            [string]$Field
        )

        return $Frontmatter -replace "(?m)^${Field}:.*\r?\n?", ''
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

    function Set-DeferFlag {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$VaultRoot,

            [Parameter(Mandatory)]
            [string]$AuditLogDir
        )

        $content = Get-Content -Path $Path -Raw -Encoding utf8
        $parsed = Get-ParsedFrontmatter -Content $content

        if (-not $parsed.HasFrontmatter) {
            # Create frontmatter block
            $frontmatter = "metadata_review: pending`n"
            if ($Reason) {
                $frontmatter += "metadata_review_note: `"$Reason`"`n"
            }
            $newContent = "---`n$frontmatter---`n$($parsed.Body)"
        }
        else {
            $frontmatter = Set-FrontmatterField -Frontmatter $parsed.Frontmatter -Field 'metadata_review' -Value 'pending'
            if ($Reason) {
                $frontmatter = Set-FrontmatterField -Frontmatter $frontmatter -Field 'metadata_review_note' -Value "`"$Reason`""
            }
            else {
                $frontmatter = Remove-FrontmatterField -Frontmatter $frontmatter -Field 'metadata_review_note'
            }
            $newContent = "---`n$frontmatter---`n$($parsed.Body)"
        }

        $relativePath = $Path.Replace($VaultRoot, '').TrimStart('\', '/')
        $reasonSuffix = if ($Reason) { " (reason: $Reason)" } else { '' }

        if ($PSCmdlet.ShouldProcess($relativePath, "Stamp metadata_review: pending")) {
            Set-Content -Path $Path -Value $newContent -NoNewline -Encoding utf8NoBOM
            Write-AuditEntry -LogDir $AuditLogDir -Message "DEFER: ``$relativePath`` stamped metadata_review: pending$reasonSuffix"
        }
    }
}

End {}
