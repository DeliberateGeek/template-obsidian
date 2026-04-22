#Requires -Version 7.0

<#
.SYNOPSIS
    Validates a vault's vault-metadata.yaml against metadata-schema.yaml.

.DESCRIPTION
    Performs structural validation of a vault's canonical metadata file
    against the schema shipped with the Obsidian metadata framework.
    Emits per-finding lines to stdout describing any violations.

    Exit codes follow the framework convention documented in
    .claude/Claude Context/framework-scripts-reference.md:

        0 - Validation passed; zero findings
        1 - Validation ran; structural findings reported
        2 - Validator could not run (environment or framework problem)

    Prerequisites:
        - PowerShell 7+
        - powershell-yaml module (Install-Module -Name powershell-yaml)

.PARAMETER MetadataPath
    Path to the vault's vault-metadata.yaml. Required.

.PARAMETER SchemaPath
    Path to the metadata-schema.yaml. Optional. Defaults to
    .claude/Claude Context/metadata-schema.yaml relative to the metadata
    file's nearest .obsidian/ ancestor (vault root).

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataValidate.ps1 `
        -MetadataPath "🫥 Meta/vault-metadata.yaml"

.EXAMPLE
    pwsh.exe -File .claude/scripts/Invoke-MetadataValidate.ps1 `
        -MetadataPath .claude/scripts/test-fixtures/vault-metadata.valid.yaml `
        -SchemaPath ".claude/Claude Context/metadata-schema.yaml"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$MetadataPath,

    [Parameter()]
    [string]$SchemaPath
)

Process {
    $metadata = Read-YamlFile -Path $script:resolvedMetadataPath -Label 'vault-metadata.yaml'
    $schema = Read-YamlFile -Path $script:resolvedSchemaPath -Label 'metadata-schema.yaml'

    $findings = [System.Collections.Generic.List[string]]::new()

    Test-TopLevelSections -Metadata $metadata -Findings $findings
    if ($findings.Count -gt 0) {
        # Missing top-level sections make downstream checks meaningless; stop early.
        Write-Findings -Findings $findings
        exit 1
    }

    Test-VaultSection -Metadata $metadata -Findings $findings
    Test-ContentTypes -Metadata $metadata -Findings $findings
    Test-Topics -Metadata $metadata -Findings $findings
    Test-Properties -Metadata $metadata -Findings $findings
    Test-CrossReferences -Metadata $metadata -Findings $findings
    Test-DeprecatedSection -Metadata $metadata -Findings $findings

    if ($findings.Count -eq 0) {
        Write-Host "  ✅ No findings. vault-metadata.yaml conforms to metadata-schema.yaml." -ForegroundColor Green
        exit 0
    }

    Write-Findings -Findings $findings
    exit 1
}

Begin {
    $ErrorActionPreference = 'Stop'

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

See .claude/Claude Context/framework-scripts-reference.md for details.
"@
        }

        Import-Module powershell-yaml -ErrorAction Stop
    }

    function Resolve-InputPath {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        if ([System.IO.Path]::IsPathRooted($Path)) {
            return $Path
        }
        return (Join-Path (Get-Location) $Path)
    }

    function Resolve-VaultRoot {
        param(
            [Parameter(Mandatory)]
            [string]$StartPath
        )

        $dir = if (Test-Path $StartPath -PathType Container) {
            $StartPath
        } else {
            Split-Path $StartPath -Parent
        }

        while ($dir) {
            if (Test-Path (Join-Path $dir '.obsidian')) {
                return $dir
            }
            $parent = Split-Path $dir -Parent
            if ($parent -eq $dir) { break }
            $dir = $parent
        }

        return $null
    }

    function Resolve-SchemaPath {
        param(
            [Parameter(Mandatory)]
            [string]$MetadataPath,

            [Parameter()]
            [string]$ExplicitSchemaPath
        )

        if ($ExplicitSchemaPath) {
            return (Resolve-InputPath -Path $ExplicitSchemaPath)
        }

        $vaultRoot = Resolve-VaultRoot -StartPath $MetadataPath
        if ($vaultRoot) {
            return (Join-Path $vaultRoot '.claude' 'Claude Context' 'metadata-schema.yaml')
        }

        # Fallback: relative to the script's own location (e.g., when running
        # against test fixtures from inside template-obsidian's working tree).
        $scriptRoot = $PSScriptRoot
        $candidate = Join-Path $scriptRoot '..' 'Claude Context' 'metadata-schema.yaml'
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }

        Exit-Environment -Message "Could not locate metadata-schema.yaml. Pass -SchemaPath explicitly."
    }

    function Read-YamlFile {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Label
        )

        if (-not (Test-Path $Path)) {
            Exit-Environment -Message "$Label not found at: $Path"
        }

        try {
            $content = Get-Content -Path $Path -Raw -Encoding utf8
            return (ConvertFrom-Yaml -Yaml $content)
        }
        catch {
            Exit-Environment -Message "Could not parse $Label as YAML: $_"
        }
    }

    function Test-IsKebabCase {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Value
        )

        # Allow empty check separately; kebab-case pattern is lowercase
        # letters + digits + single hyphens, starting with a letter.
        return ($Value -match '^[a-z][a-z0-9]*(-[a-z0-9]+)*$')
    }

    function Test-IsInt {
        param(
            [Parameter()]
            [object]$Value
        )

        if ($null -eq $Value) { return $false }
        if ($Value -is [int] -or $Value -is [long]) { return $true }
        # Accept int-parseable numeric strings but not arbitrary strings.
        if ($Value -is [string]) { return $false }
        return $false
    }

    function Add-Finding {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings,

            [Parameter(Mandatory)]
            [string]$Section,

            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Message
        )

        $Findings.Add("[$Section] $Path — $Message")
    }

    function Test-TopLevelSections {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $required = @('vault', 'content_types', 'topics', 'properties', 'deprecated')
        foreach ($key in $required) {
            if (-not $Metadata.ContainsKey($key)) {
                Add-Finding -Findings $Findings -Section 'top-level' -Path $key `
                    -Message "Required top-level section is missing."
            }
        }
    }

    function Test-VaultSection {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $vault = $Metadata['vault']
        if (-not $vault.ContainsKey('name') -or -not $vault['name'] -or [string]::IsNullOrWhiteSpace([string]$vault['name'])) {
            Add-Finding -Findings $Findings -Section 'vault' -Path 'vault.name' `
                -Message "Must be a non-empty string."
        }

        if ($vault.ContainsKey('promotion_threshold') -and -not (Test-IsInt -Value $vault['promotion_threshold'])) {
            Add-Finding -Findings $Findings -Section 'vault' -Path 'vault.promotion_threshold' `
                -Message "Must be an integer; got '$($vault['promotion_threshold'])' ($($vault['promotion_threshold'].GetType().Name))."
        }
    }

    function Test-ContentTypes {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $types = $Metadata['content_types']
        if ($null -eq $types) { return }

        for ($i = 0; $i -lt $types.Count; $i++) {
            $entry = $types[$i]
            $pathBase = "content_types[$i]"

            if (-not $entry.ContainsKey('id') -or [string]::IsNullOrWhiteSpace([string]$entry['id'])) {
                Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.id" `
                    -Message "Required; must be a non-empty string."
                continue
            }

            $id = [string]$entry['id']
            if (-not (Test-IsKebabCase -Value $id)) {
                Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.id" `
                    -Message "'$id' is not kebab-case (lowercase letters/digits/hyphens, starting with a letter)."
            }

            if (-not $entry.ContainsKey('description') -or [string]::IsNullOrWhiteSpace([string]$entry['description'])) {
                Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.description" `
                    -Message "Required; must be a non-empty string."
            }

            if (-not $entry.ContainsKey('lifecycle') -or $null -eq $entry['lifecycle']) {
                Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.lifecycle" `
                    -Message "Required; must declare an 'applicable' key at minimum."
                continue
            }

            $lifecycle = $entry['lifecycle']
            if (-not $lifecycle.ContainsKey('applicable')) {
                Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.lifecycle.applicable" `
                    -Message "Required boolean."
                continue
            }

            if ($lifecycle['applicable'] -eq $true) {
                if (-not $lifecycle.ContainsKey('property') -or [string]::IsNullOrWhiteSpace([string]$lifecycle['property'])) {
                    Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.lifecycle.property" `
                        -Message "Required when lifecycle.applicable is true."
                }
                if (-not $lifecycle.ContainsKey('values') -or $null -eq $lifecycle['values'] -or $lifecycle['values'].Count -eq 0) {
                    Add-Finding -Findings $Findings -Section 'content_types' -Path "$pathBase.lifecycle.values" `
                        -Message "Required non-empty list when lifecycle.applicable is true."
                }
            }
        }
    }

    function Test-Topics {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $topics = $Metadata['topics']
        if ($null -eq $topics -or $topics.Count -eq 0) { return }

        for ($i = 0; $i -lt $topics.Count; $i++) {
            $entry = $topics[$i]
            $pathBase = "topics[$i]"

            if (-not $entry.ContainsKey('id') -or [string]::IsNullOrWhiteSpace([string]$entry['id'])) {
                Add-Finding -Findings $Findings -Section 'topics' -Path "$pathBase.id" `
                    -Message "Required; must be a non-empty string."
                continue
            }

            $id = [string]$entry['id']
            if (-not (Test-IsKebabCase -Value $id)) {
                Add-Finding -Findings $Findings -Section 'topics' -Path "$pathBase.id" `
                    -Message "'$id' is not kebab-case (lowercase letters/digits/hyphens, starting with a letter)."
            }
        }
    }

    function Test-Properties {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $properties = $Metadata['properties']
        if ($null -eq $properties) { return }

        $validTypes = @('string', 'enum', 'int', 'date', 'link')
        $validCardinalities = @('single', 'multi')

        for ($i = 0; $i -lt $properties.Count; $i++) {
            $entry = $properties[$i]
            $pathBase = "properties[$i]"

            if (-not $entry.ContainsKey('name') -or [string]::IsNullOrWhiteSpace([string]$entry['name'])) {
                Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.name" `
                    -Message "Required; must be a non-empty string."
                continue
            }

            $propName = [string]$entry['name']

            if (-not $entry.ContainsKey('type')) {
                Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.type" `
                    -Message "Required; must be one of: $($validTypes -join ', ')."
            } else {
                $type = [string]$entry['type']
                if ($type -notin $validTypes) {
                    Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.type" `
                        -Message "'$type' not in allowed types: $($validTypes -join ', ')."
                }
                if ($type -eq 'enum') {
                    if (-not $entry.ContainsKey('values') -or $null -eq $entry['values'] -or $entry['values'].Count -eq 0) {
                        Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.values" `
                            -Message "Required non-empty list when type is 'enum' (property: $propName)."
                    }
                }
            }

            if (-not $entry.ContainsKey('cardinality')) {
                Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.cardinality" `
                    -Message "Required; must be one of: $($validCardinalities -join ', ')."
            } else {
                $card = [string]$entry['cardinality']
                if ($card -notin $validCardinalities) {
                    Add-Finding -Findings $Findings -Section 'properties' -Path "$pathBase.cardinality" `
                        -Message "'$card' not in allowed cardinalities: $($validCardinalities -join ', ')."
                }
            }
        }
    }

    function Test-CrossReferences {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $properties = $Metadata['properties']
        if ($null -eq $properties) { return }

        $declaredNames = @($properties | ForEach-Object {
            if ($_.ContainsKey('name')) { [string]$_['name'] }
        })

        $types = $Metadata['content_types']
        if ($null -eq $types) { return }

        for ($i = 0; $i -lt $types.Count; $i++) {
            $entry = $types[$i]
            $pathBase = "content_types[$i]"

            if (-not $entry.ContainsKey('properties') -or $null -eq $entry['properties']) { continue }
            $propsBlock = $entry['properties']

            foreach ($listKey in @('required', 'optional')) {
                if (-not $propsBlock.ContainsKey($listKey) -or $null -eq $propsBlock[$listKey]) { continue }
                $list = $propsBlock[$listKey]
                for ($j = 0; $j -lt $list.Count; $j++) {
                    $refName = [string]$list[$j]
                    if ($refName -notin $declaredNames) {
                        Add-Finding -Findings $Findings -Section 'cross-reference' `
                            -Path "$pathBase.properties.$listKey[$j]" `
                            -Message "References property '$refName' not declared in top-level properties registry."
                    }
                }
            }
        }
    }

    function Test-DeprecatedSection {
        param(
            [Parameter(Mandatory)]
            [object]$Metadata,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        $deprecated = $Metadata['deprecated']
        if ($null -eq $deprecated) { return }

        foreach ($key in @('tags', 'properties')) {
            if (-not $deprecated.ContainsKey($key)) {
                Add-Finding -Findings $Findings -Section 'deprecated' -Path "deprecated.$key" `
                    -Message "Required key; use an empty list ([]) if unused."
            }
        }
    }

    function Write-Findings {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$Findings
        )

        Write-Host "  🚨 $($Findings.Count) finding(s):" -ForegroundColor Yellow
        foreach ($finding in $Findings) {
            Write-Host "    $finding"
        }
    }

    # =========================================================================
    # Entry setup
    # =========================================================================

    Assert-YamlModule

    $script:resolvedMetadataPath = Resolve-InputPath -Path $MetadataPath
    if (-not (Test-Path $script:resolvedMetadataPath)) {
        Exit-Environment -Message "vault-metadata.yaml not found at: $script:resolvedMetadataPath"
    }

    $script:resolvedSchemaPath = Resolve-SchemaPath `
        -MetadataPath $script:resolvedMetadataPath `
        -ExplicitSchemaPath $SchemaPath

    if (-not (Test-Path $script:resolvedSchemaPath)) {
        Exit-Environment -Message "metadata-schema.yaml not found at: $script:resolvedSchemaPath"
    }
}

End {}
