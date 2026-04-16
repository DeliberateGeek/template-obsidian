#Requires -Version 7.0

<#
.SYNOPSIS
    Deletes audit log files older than the retention window.

.DESCRIPTION
    Lists audit log files in the specified directory that are older than the
    retention threshold (default 90 days) and deletes them. Logs the cleanup
    action to the current day's audit log file.

    Part of the /audit-metadata Skill's housekeeping pass.

.PARAMETER AuditLogDir
    Path to the audit log directory. If not specified, auto-detected from
    the vault root (looks for a Meta/Audit Logs/ folder).

.PARAMETER RetentionDays
    Number of days to retain audit log files. Files older than this threshold
    are deleted. Defaults to 90.

.EXAMPLE
    pwsh.exe -File .claude/scripts/Remove-MetadataAuditLogs.ps1

.EXAMPLE
    pwsh.exe -File .claude/scripts/Remove-MetadataAuditLogs.ps1 -RetentionDays 30

.EXAMPLE
    pwsh.exe -File .claude/scripts/Remove-MetadataAuditLogs.ps1 -AuditLogDir "C:/Vaults/MyVault/Meta/Audit Logs"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AuditLogDir,

    [int]$RetentionDays = 90
)

Process {
    $resolvedLogDir = Resolve-LogDirectory
    Assert-LogDirectoryExists -Path $resolvedLogDir

    if ($WhatIfPreference) {
        Write-Host "  ⚠️ [WHATIF MODE] No changes will be made" -ForegroundColor Yellow
    }

    $expiredFiles = Get-ExpiredLogFiles -LogDir $resolvedLogDir -RetentionDays $RetentionDays

    if ($expiredFiles.Count -eq 0) {
        Write-Host "  ℹ️ No audit log files older than $RetentionDays days." -ForegroundColor DarkGray
        exit 0
    }

    $removedCount = Remove-ExpiredFiles -Files $expiredFiles -LogDir $resolvedLogDir
}

Begin {
    $ErrorActionPreference = 'Stop'

    # =========================================================================
    # Helper Functions
    # =========================================================================

    function Resolve-LogDirectory {
        if ($AuditLogDir) {
            if ([System.IO.Path]::IsPathRooted($AuditLogDir)) {
                return $AuditLogDir
            }
            return Join-Path (Get-Location) $AuditLogDir
        }

        # Auto-detect from current directory (assume we're in vault root)
        $vaultRoot = Get-Location
        $metaDir = Get-ChildItem -Path $vaultRoot -Directory |
            Where-Object { $_.Name -match 'Meta$' } |
            Select-Object -First 1

        if ($metaDir) {
            return Join-Path $metaDir.FullName 'Audit Logs'
        }

        return Join-Path $vaultRoot 'Meta' 'Audit Logs'
    }

    function Assert-LogDirectoryExists {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if (-not (Test-Path $Path)) {
            Write-Host "  ℹ️ Audit log directory does not exist: $Path" -ForegroundColor DarkGray
            Write-Host "  ℹ️ Nothing to clean up." -ForegroundColor DarkGray
            exit 0
        }
    }

    function Get-ExpiredLogFiles {
        param(
            [Parameter(Mandatory)]
            [string]$LogDir,

            [Parameter(Mandatory)]
            [int]$RetentionDays
        )

        $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

        # Audit log files follow YYYY-MM-DD.md naming convention
        $logFiles = Get-ChildItem -Path $LogDir -Filter '*.md' |
            Where-Object {
                $_.Name -match '^\d{4}-\d{2}-\d{2}\.md$' -and
                $_.LastWriteTime -lt $cutoffDate
            } |
            Sort-Object Name

        return @($logFiles)
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

    function Remove-ExpiredFiles {
        param(
            [Parameter(Mandatory)]
            [array]$Files,

            [Parameter(Mandatory)]
            [string]$LogDir
        )

        $removedCount = 0

        foreach ($file in $Files) {
            if ($PSCmdlet.ShouldProcess($file.Name, "Remove expired audit log")) {
                Remove-Item -Path $file.FullName -Force
                $removedCount++
            }
        }

        if ($removedCount -gt 0 -and -not $WhatIfPreference) {
            Write-AuditEntry -LogDir $LogDir -Message "CLEANUP: removed $removedCount expired audit log file(s) (retention: ${RetentionDays}d)"
        }

        return $removedCount
    }
}

End {}
