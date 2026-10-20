function Read-AACAlzLibrary {
    <#
    .SYNOPSIS
        Reads a local copy of the Azure Landing Zones Library
        (github.com/Azure/Azure-Landing-Zones-Library): an architecture's
        management groups, the archetypes each one gets, and the policy
        assignments each archetype makes.
    .DESCRIPTION
        -Path is the library's folder (the repository root, or its
        platform\alz folder). Nothing is downloaded: clone or download the
        library yourself, at the release you want to compare with.
        Returns @{
          Architecture      the architecture's name
          ManagementGroups  @(@{ Id; DisplayName; ParentId; Archetypes })
          Archetypes        name -> @(assignment names)
          Assignments       name -> @{ Name; DisplayName; DefinitionId;
                            Enforcement; Description; File }
          Version           the library metadata's name and path
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Architecture = 'alz'
    )

    $root = $Path
    if (-not (Test-Path -LiteralPath (Join-Path -Path $root -ChildPath 'archetype_definitions'))) {
        $nested = Join-Path -Path $root -ChildPath 'platform/alz'
        if (Test-Path -LiteralPath (Join-Path -Path $nested -ChildPath 'archetype_definitions')) { $root = $nested }
        else {
            $problem = [System.IO.DirectoryNotFoundException]::new("Azure Admin Console found no Azure Landing Zones Library at $Path (no archetype_definitions folder).")
            $problem.Data['AACHint'] = 'Clone it first: git clone https://github.com/Azure/Azure-Landing-Zones-Library, then pass that folder (or its platform\alz folder) as -LibraryPath.'
            throw $problem
        }
    }
    $readJson = { param([string] $File) Get-Content -LiteralPath $File -Raw | ConvertFrom-Json -AsHashtable -Depth 50 }

    $architectureFile = Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'architecture_definitions') -Filter "$Architecture.alz_architecture_definition.json" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $architectureFile) {
        $known = @(Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'architecture_definitions') -Filter '*.alz_architecture_definition.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name -replace '\.alz_architecture_definition\.json$', '' })
        throw "Azure Admin Console found no architecture '$Architecture' in the library. It has: $($known -join ', ')."
    }
    $design = & $readJson $architectureFile.FullName
    $groups = @(foreach ($g in @($design['management_groups'])) {
            @{ Id = [string]$g['id']; DisplayName = [string]$g['display_name']; ParentId = [string]$g['parent_id']; Archetypes = @($g['archetypes']) }
        })

    $archetypes = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'archetype_definitions') -Filter '*.alz_archetype_definition.json' -File) {
        $a = & $readJson $file.FullName
        $archetypes[[string]$a['name']] = @($a['policy_assignments'] | Where-Object { $_ })
    }
    $assignments = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'policy_assignments') -Filter '*.alz_policy_assignment.json' -File) {
        $a = & $readJson $file.FullName
        $p = $a['properties']
        $assignments[([string]$a['name']).ToLowerInvariant()] = @{
            Name         = [string]$a['name']
            DisplayName  = [string]$p['displayName']
            DefinitionId = [string]$p['policyDefinitionId']
            Enforcement  = $(if ($p['enforcementMode']) { [string]$p['enforcementMode'] } else { 'Default' })
            Description  = [string]$p['description']
            File         = $file.Name
        }
    }
    $metadataFile = Join-Path -Path $root -ChildPath 'alz_library_metadata.json'
    $metadata = if (Test-Path -LiteralPath $metadataFile) { & $readJson $metadataFile } else { @{} }
    @{
        Architecture     = [string]$design['name']
        ManagementGroups = $groups
        Archetypes       = $archetypes
        Assignments      = $assignments
        Version          = "$($metadata['display_name']) ($($metadata['path']))"
        Path             = $root
    }
}
