#Requires -Version 7.0

<#
.SYNOPSIS
    Shared frontmatter and tag parsing primitives for the Obsidian metadata framework scripts.

.DESCRIPTION
    Provides parsing helpers consumed by Invoke-MetadataNormalize.ps1 and
    Invoke-MetadataScan.ps1. Scope is intentionally narrow: frontmatter
    extraction, tag-region identification, and tag-line formatting. No
    vault-walking, no YAML parsing of vault-metadata.yaml (scripts do that
    directly via powershell-yaml).

    Import with:
        Import-Module "$PSScriptRoot/MetadataParsing.psm1" -Force

    The -Force flag ensures test runs pick up in-flight edits without
    restarting the PowerShell session.
#>

$ErrorActionPreference = 'Stop'

function Get-ParsedFrontmatter {
    <#
    .SYNOPSIS
        Splits a markdown note's content into frontmatter and body.
    .OUTPUTS
        Hashtable with keys: Frontmatter (string, without --- delimiters),
        Body (string), HasFrontmatter (bool).
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Content
    )

    if ([string]::IsNullOrEmpty($Content)) {
        return @{
            Frontmatter    = ''
            Body           = ''
            HasFrontmatter = $false
        }
    }

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
    <#
    .SYNOPSIS
        Locates the `tags:` region within a frontmatter text block.
    .OUTPUTS
        $null if no top-level tags key exists. Otherwise a hashtable:
            Shape   = 'Inline' | 'Block' | 'Scalar' | 'Empty'
            Tags    = string[]  (parsed tag values; empty for Empty shape)
            Start   = int       (character index of line start in $Frontmatter)
            Length  = int       (characters to remove, including trailing newline)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Frontmatter
    )

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
            $inner -split ',' | ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ -ne '' }
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
            $trimmed = $line.TrimEnd("`r", "`n")
            if ($trimmed -match '^\s+-\s+(?<val>.+?)\s*$') {
                $tags.Add($Matches['val'].Trim('"', "'"))
                $cursor = $nextNewline + 1
                continue
            }
            if ($trimmed -match '^\s*$') {
                break
            }
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
        Tags   = [string[]]@($tail.Trim('"', "'"))
        Start  = $lineStart
        Length = $lineEnd - $lineStart
    }
}

function ConvertTo-InlineTagsLine {
    <#
    .SYNOPSIS
        Formats a tag array as an inline-array YAML line.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Tags
    )

    if ($Tags.Count -eq 0) { return 'tags: []' }
    return 'tags: [' + ($Tags -join ', ') + ']'
}

Export-ModuleMember -Function Get-ParsedFrontmatter, Get-TagsRegion, ConvertTo-InlineTagsLine
