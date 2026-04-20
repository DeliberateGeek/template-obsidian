# Framework Scripts Reference

Reference documentation for the PowerShell scripts shipped under `.claude/scripts/` as part of the Obsidian metadata framework. Covers runtime prerequisites and the exit-code convention that framework scripts follow.

This document is read by contributors maintaining the scripts and by Skills (`/init-vault-metadata-framework`, `/audit-metadata`, `/update-metadata-framework`) that invoke them.

## Prerequisites

### `powershell-yaml` module

Required by any script that parses YAML (currently `Invoke-MetadataValidate.ps1`). Install once per machine:

```powershell
Install-Module -Name powershell-yaml -Scope CurrentUser -Force
```

Tested against `powershell-yaml` v0.4.x. Scripts that require this module check for its availability and exit with code 2 (environment error) if it is missing, surfacing the install command above.

### PowerShell 7+

All framework scripts declare `#Requires -Version 7.0`. Windows PowerShell 5.1 is not supported.

## Exit-code convention

Framework scripts that produce actionable findings (validators, auditors) follow a three-state exit-code convention so callers can distinguish user-content problems from environment problems:

| Code | Meaning | Caller behavior |
|------|---------|-----------------|
| **0** | Success — script ran to completion with zero findings | Proceed |
| **1** | Script ran; structural findings reported | Surface findings to the user; offer revise/abort or halt per Skill policy |
| **2** | Script could not run — environment or framework problem | Halt with the surfaced environment error (do not treat as user-correctable) |

Examples of exit 2 causes: `powershell-yaml` module missing, schema file missing or unreadable, schema file itself is malformed YAML, metadata file path does not exist.

Examples of exit 1 causes: missing required top-level section in `vault-metadata.yaml`, invalid enum value, id not in kebab-case, cross-reference to an undeclared property.

### Scripts that predate this convention

`Invoke-MetadataNormalize.ps1`, `Set-MetadataDefer.ps1`, and `Remove-MetadataAuditLogs.ps1` currently use a simpler 0/1 convention (success/error). They do not surface findings in the validator sense — they either apply a mutation or they do not. No action required; the 0/1/2 convention applies to new scripts that introduce a findings-vs-environment distinction.

## Script inventory

| Script | Purpose | Exit convention |
|--------|---------|-----------------|
| `Invoke-MetadataNormalize.ps1` | Normalize declared alias tags to canonical form in a note | 0/1 |
| `Invoke-MetadataValidate.ps1` | Validate `vault-metadata.yaml` against `metadata-schema.yaml` | 0/1/2 |
| `Remove-MetadataAuditLogs.ps1` | Delete daily audit logs older than the retention threshold | 0/1 |
| `Set-MetadataDefer.ps1` | Stamp `metadata_review: pending` on a note | 0/1 |

## Related

- Schema definition: `.claude/Claude Context/metadata-schema.yaml`
- Philosophy and boundary rules: `.claude/Claude Context/metadata-philosophy.md`
- Worked examples: `.claude/Claude Context/metadata-examples.md`
