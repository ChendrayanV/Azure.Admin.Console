function ConvertTo-AACDevOpsSbom {
    <#
    .SYNOPSIS
        Builds Invoke-AACADOAssessment's SBOM tab for one organization: which
        build pipelines produce a software bill of materials, what is in the
        SBOMs their latest successful runs published, the licences, and what
        to fix.
    .DESCRIPTION
        No calls. Inputs: the organization's pipeline rows (their Sbom,
        Deploy and Publish columns say what was found in the steps), the
        SBOM tools' evidence, and Read-AACDevOpsSbom's result (-Sbom, by
        'project|pipeline ID'; empty with -SbomRead off).

        SBOMs read: SPDX 2.2 and 2.3 JSON (the Microsoft SBOM Tool's
        _manifest/spdx_2.2/manifest.spdx.json), SPDX 3.0 JSON-LD
        (_manifest/spdx_3.0) and CycloneDX JSON. The package the document
        describes (the build itself) is not counted as a component.

        Each component is complete when it has the NTIA minimum elements a
        machine can check: a name, a version, a supplier and a unique ID (a
        package URL). Licences are sorted Permissive, Weak copyleft (LGPL,
        MPL, EPL...), Strong copyleft (GPL, AGPL, SSPL...) or Unknown
        (NOASSERTION, none) - an OR expression takes its most permissive
        choice, an AND its strictest part.

        Findings (area Supply chain): a pipeline that deploys or publishes
        with no SBOM generator (Medium); an SBOM generated but not in the
        latest successful run's artifacts (Low); an SBOM under 80% complete
        (Low); strong copyleft components (Low); mostly unknown licences
        (Info); an SBOM never validated (Info).

        Returns @{ Pipelines; Components; Licenses; Findings; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Pipeline = @(),

        # The evidence rows of the SBOM category.
        [AllowEmptyCollection()]
        [object[]] $Evidence = @(),

        [hashtable] $Sbom = @{},

        [switch] $SbomRead,

        # Components listed per SBOM, at most.
        [int] $MaxComponents = 5000
    )

    $member = { param($Item, [string] $Path) Get-AACMember -InputObject $Item -Path $Path }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $blank = { param([string] $Text) -not $Text -or $Text -in 'NOASSERTION', 'NONE' }

    # --- Licences: an SPDX expression's kind -----------------------------------------------------------------
    $kindRank = @{ Permissive = 0; 'Weak copyleft' = 1; 'Strong copyleft' = 2; Unknown = 3 }
    $partKind = {
        param([string] $Id)
        $id = $Id.Trim(' ', '(', ')')
        if (& $blank $id) { 'Unknown' }
        elseif ($id -match '(?i)^(AGPL|SSPL|OSL|EUPL|CPAL|RPL)|(?i)^GPL') { 'Strong copyleft' }
        elseif ($id -match '(?i)^(LGPL|MPL|EPL|CDDL|CPL|MS-RL|CECILL)') { 'Weak copyleft' }
        elseif ($id -match '(?i)^LicenseRef-') { 'Unknown' }
        else { 'Permissive' }
    }
    $licenseKind = {
        param([string] $Expression)
        if (& $blank $Expression) { return 'Unknown' }
        # OR: the most permissive choice; AND (and WITH): the strictest part.
        $choices = foreach ($choice in ($Expression -split '\s+OR\s+')) {
            $parts = @($choice -split '\s+AND\s+' | ForEach-Object { ($_ -split '\s+WITH\s+')[0] } | ForEach-Object { & $partKind $_ })
            @($parts | Sort-Object { $kindRank[$_] } -Descending)[0]
        }
        @($choices | Sort-Object { $kindRank[$_] })[0]
    }

    # --- An SBOM document, whatever its format, as one shape -------------------------------------------------
    $normalise = {
        param([System.Collections.IDictionary] $Doc)
        $out = @{ Format = ''; Name = ''; Created = ''; Tools = ''; Files = $null; Components = [System.Collections.Generic.List[hashtable]]::new(); Relationships = 0 }
        $add = {
            param([string] $Name, [string] $Version, [string] $Supplier, [string] $License, [string] $Purl)
            $out.Components.Add(@{ Name = $Name; Version = $Version; Supplier = $Supplier; License = $License; Purl = $Purl })
        }
        if ($Doc.Contains('spdxVersion')) {
            # SPDX 2.x: packages, files and relationships; the document describes the build's own package.
            $out.Format = ([string]$Doc['spdxVersion']) -replace '^SPDX-', 'SPDX '
            $out.Name = [string]$Doc['name']
            $out.Created = [string](& $member $Doc 'creationInfo.created')
            $out.Tools = (@(& $list (& $member $Doc 'creationInfo.creators')) | Where-Object { [string]$_ -like 'Tool:*' } | ForEach-Object { ([string]$_ -replace '^Tool:\s*', '') }) -join ', '
            $out.Files = @(& $list $Doc['files']).Count
            $relationships = @(& $list $Doc['relationships'])
            $out.Relationships = $relationships.Count
            $roots = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($id in @(& $list $Doc['documentDescribes'])) { [void]$roots.Add([string]$id) }
            foreach ($r in $relationships) { if ([string]$r['relationshipType'] -eq 'DESCRIBES' -and [string]$r['spdxElementId'] -eq 'SPDXRef-DOCUMENT') { [void]$roots.Add([string]$r['relatedSpdxElement']) } }
            foreach ($p in @(& $list $Doc['packages'])) {
                if ($roots.Contains([string]$p['SPDXID'])) { continue }
                $purl = [string](@(& $list $p['externalRefs']) | Where-Object { [string]$_['referenceType'] -eq 'purl' } | ForEach-Object { [string]$_['referenceLocator'] } | Select-Object -First 1)
                $license = [string]$p['licenseConcluded']
                if (& $blank $license) { $license = [string]$p['licenseDeclared'] }
                & $add ([string]$p['name']) ([string]$p['versionInfo']) (([string]$p['supplier']) -replace '^(Organization|Person):\s*', '') $license $purl
            }
        }
        elseif ($Doc.Contains('@graph')) {
            # SPDX 3.0 (JSON-LD): elements by spdxId; licences and the root through relationships.
            $out.Format = 'SPDX 3.0'
            $graph = @(& $list $Doc['@graph'])
            $byId = @{}
            foreach ($e in $graph) { if ($e -is [System.Collections.IDictionary] -and $e['spdxId']) { $byId[[string]$e['spdxId']] = $e } }
            $roots = [System.Collections.Generic.HashSet[string]]::new()
            $licenseOf = @{}
            foreach ($e in $graph) {
                $type = [string]$e['type']
                if ($type -in 'SpdxDocument', 'software_Sbom') { foreach ($root in @(& $list $e['rootElement'])) { [void]$roots.Add([string]$root) } }
                if ($type -eq 'CreationInfo' -and -not $out.Created) { $out.Created = [string]$e['created'] }
                if ($type -eq 'Tool' -and $e['name']) { $out.Tools = (@($out.Tools, [string]$e['name']) | Where-Object { $_ }) -join ', ' }
                if ($type -eq 'software_File') { $out.Files = 1 + [int]$out.Files }
                if ($type -eq 'Relationship') {
                    $out.Relationships++
                    if ([string]$e['relationshipType'] -in 'hasConcludedLicense', 'hasDeclaredLicense') {
                        $target = $byId[[string]@(& $list $e['to'])[0]]
                        $expression = if ($target) { [string]$(@($target['simplelicensing_licenseExpression'], $target['name']) | Where-Object { $_ } | Select-Object -First 1) } else { '' }
                        if ($expression -and ([string]$e['relationshipType'] -eq 'hasConcludedLicense' -or -not $licenseOf.Contains([string]$e['from']))) { $licenseOf[[string]$e['from']] = $expression }
                    }
                }
            }
            foreach ($e in $graph) {
                if ([string]$e['type'] -ne 'software_Package' -or $roots.Contains([string]$e['spdxId'])) { continue }
                $purl = [string](@(& $list $e['externalIdentifier']) | Where-Object { [string]$_['externalIdentifierType'] -eq 'packageUrl' } | ForEach-Object { [string]$_['identifier'] } | Select-Object -First 1)
                if (-not $purl) { $purl = [string]$e['software_packageUrl'] }
                $supplier = $byId[[string]$e['suppliedBy']]
                & $add ([string]$e['name']) ([string]$e['software_packageVersion']) $(if ($supplier) { [string]$supplier['name'] } else { '' }) ([string]$licenseOf[[string]$e['spdxId']]) $purl
            }
        }
        elseif ([string]$Doc['bomFormat'] -eq 'CycloneDX') {
            # CycloneDX: components (nested ones too); metadata.component is the build itself.
            $out.Format = "CycloneDX $($Doc['specVersion'])".Trim()
            $out.Name = [string](& $member $Doc 'metadata.component.name')
            $out.Created = [string](& $member $Doc 'metadata.timestamp')
            $tools = & $member $Doc 'metadata.tools'
            # CycloneDX 1.4 lists the tools; 1.5 and later nest them under components.
            $toolItems = if ($tools -is [System.Collections.IDictionary]) { @(& $list $tools['components']) } else { @(& $list $tools) }
            $out.Tools = (@($toolItems) | Where-Object { $_ -is [System.Collections.IDictionary] -and $_['name'] } | ForEach-Object { "$($_['name']) $($_['version'])".Trim() } | Select-Object -Unique) -join ', '
            $out.Relationships = @(& $list $Doc['dependencies']).Count
            $queue = [System.Collections.Generic.Queue[object]]::new()
            foreach ($c in @(& $list $Doc['components'])) { $queue.Enqueue($c) }
            while ($queue.Count) {
                $c = $queue.Dequeue()
                foreach ($child in @(& $list $c['components'])) { $queue.Enqueue($child) }
                $licenses = @(& $list $c['licenses'] | ForEach-Object { if ($_['expression']) { [string]$_['expression'] } else { [string]$(@((& $member $_ 'license.id'), (& $member $_ 'license.name')) | Where-Object { $_ } | Select-Object -First 1) } } | Where-Object { $_ })
                $supplier = [string]$(@((& $member $c 'supplier.name'), $c['publisher'], $c['author']) | Where-Object { $_ } | Select-Object -First 1)
                & $add ([string]$c['name']) ([string]$c['version']) $supplier ($licenses -join ' AND ') ([string]$c['purl'])
            }
        }
        $out
    }

    # --- Per pipeline ----------------------------------------------------------------------------------------
    $evidenceOf = @{}
    foreach ($e in $Evidence) {
        $key = "$($e.Project)|$($e.PipelineId)"
        if (-not $evidenceOf.Contains($key)) { $evidenceOf[$key] = [System.Collections.Generic.List[object]]::new() }
        $evidenceOf[$key].Add($e)
    }
    $pipelineRows = [System.Collections.Generic.List[object]]::new()
    $componentRows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $find = {
        param($Row, [string] $Severity, [string] $Title, [string] $Detail, [string] $Fix)
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DevOpsFinding'; Severity = $Severity; Organization = $Row.Organization; Project = $Row.Project; Area = 'Supply chain'; Item = "$($Row.Pipeline) (#$($Row.Id))"; Finding = $Title; Detail = $Detail; Recommendation = $Fix })
    }
    $generateFix = 'Generate an SBOM after the build with the Microsoft SBOM Tool - sbom-tool generate -b <drop folder> -bc <source folder> -pn <name> -pv <version> -ps <supplier> (or the Manifest Generator task, or GenerateSBOM=true in a .NET project) - and publish the drop with its _manifest folder.'
    foreach ($p in @($Pipeline | Where-Object { $_.Kind -in 'YAML', 'Classic build' })) {
        $key = "$($p.Project)|$($p.Id)"
        $tools = @(if ($evidenceOf.Contains($key)) { $evidenceOf[$key] | ForEach-Object Tool | Select-Object -Unique })
        $generators = @($tools | Where-Object { $_ -ne 'Microsoft SBOM Tool (validate)' })
        $validated = $tools -contains 'Microsoft SBOM Tool (validate)'
        $ships = [bool]($p.Deploy -or $p.Publish)
        $read = if ($Sbom.Contains($key)) { $Sbom[$key] } else { $null }
        $doc = if ($read -and $read.Document) { & $normalise $read.Document } else { $null }
        $components = @(if ($doc) { $doc.Components })
        $complete = @($components | Where-Object { $_.Name -and $_.Version -and -not (& $blank $_.Supplier) -and $_.Purl }).Count
        $kinds = @($components | ForEach-Object { & $licenseKind $_.License })
        $copyleft = @($kinds | Where-Object { $_ -eq 'Strong copyleft' }).Count
        $unknown = @($kinds | Where-Object { $_ -eq 'Unknown' }).Count
        $status = if ($doc) { 'SBOM published' }
        elseif ($p.Yaml -in 'Not read', 'Repository disabled') { 'Steps not read' }
        elseif (-not $generators.Count) { 'No SBOM' }
        elseif ($read -and $read.Status -eq 'Not found') { 'Generated, not published' }
        else { 'Generated, not read' }
        $detail = if ($read) { [string]$read.Detail } elseif ($generators.Count -and -not $SbomRead) { 'The artifacts weren''t read (-Skip Sbom).' } else { '' }
        if ($doc -and $components.Count -gt $MaxComponents) { $detail = "The first $MaxComponents of $($components.Count) components are listed." }
        $row = [pscustomobject][ordered]@{
            PSTypeName   = 'AAC.DevOpsSbom'
            Organization = $p.Organization
            Project      = $p.Project
            Pipeline     = $p.Pipeline
            Id           = $p.Id
            Kind         = $p.Kind
            Repository   = $p.Repository
            Ships        = $(if ($ships) { 'Yes' } else { 'No' })
            Generator    = $generators -join ', '
            Validated    = $(if ($validated) { 'Yes' } else { 'No' })
            Status       = $status
            Detail       = $detail
            Run          = $(if ($read) { [string]$read.BuildNumber } else { '' })
            RunFinished  = $(if ($read -and $read.Finished) { $finished = [string]$read.Finished -replace 'T', ' '; $finished.Substring(0, [Math]::Min(16, $finished.Length)) } else { '' })
            Artifact     = $(if ($read) { [string]$read.Artifact } else { '' })
            File         = $(if ($read) { [string]$read.Path } else { '' })
            Format       = $(if ($doc) { $doc.Format } else { '' })
            CreatedBy    = $(if ($doc) { $doc.Tools } else { '' })
            Created      = $(if ($doc) { $doc.Created } else { '' })
            Components   = $(if ($doc) { $components.Count } else { $null })
            Files        = $(if ($doc) { $doc.Files } else { $null })
            Relationships = $(if ($doc) { $doc.Relationships } else { $null })
            Completeness = $(if ($components.Count) { [Math]::Round(100.0 * $complete / $components.Count, 1) } else { $null })
            UnknownLicenses = $(if ($doc) { $unknown } else { $null })
            Copyleft     = $(if ($doc) { $copyleft } else { $null })
            Url          = $(if ($read -and $read.BuildId) { ([string]$p.Url -replace '_build\?definitionId=\d+$', "_build/results?buildId=$($read.BuildId)&view=artifacts") } else { [string]$p.Url })
        }
        $pipelineRows.Add($row)
        foreach ($c in @($components | Select-Object -First $MaxComponents)) {
            $componentRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.DevOpsSbomComponent'; Organization = $p.Organization; Project = $p.Project; Pipeline = $p.Pipeline; Component = $c.Name; Version = $c.Version
                    Ecosystem = $(if ($c.Purl -match '^pkg:([^/]+)/') { $Matches[1] } else { '' }); Supplier = $(if (& $blank $c.Supplier) { '' } else { $c.Supplier })
                    License = $(if (& $blank $c.License) { '' } else { $c.License }); LicenseKind = & $licenseKind $c.License
                    Complete = [bool]($c.Name -and $c.Version -and -not (& $blank $c.Supplier) -and $c.Purl); Purl = $c.Purl
                })
        }

        # Findings: what keeps the SBOM from being there, complete and usable.
        switch ($status) {
            'No SBOM' { if ($ships) { & $find $row 'Medium' 'No SBOM' "It $(if ($p.Deploy) { 'deploys' } else { 'publishes' }), but no SBOM generator was found in its steps - what it ships can't be listed, checked for a new vulnerability or proved unchanged." $generateFix } }
            'Generated, not published' { & $find $row 'Low' 'SBOM not published' "An SBOM is generated ($($generators -join ', ')), but none is in the artifacts of the latest successful run $($row.Run)." 'Publish the drop folder with its _manifest folder (PublishPipelineArtifact@1 on the folder given to sbom-tool -b), so the SBOM travels with what it describes.' }
        }
        if ($doc) {
            if ($components.Count -and $row.Completeness -lt 80) { & $find $row 'Low' 'Incomplete SBOM' "$($components.Count - $complete) of $($components.Count) components lack a version, a supplier or a package URL (NTIA minimum elements)." 'Give sbom-tool the source folder (-bc) so component detection finds the package manifests and lock files, and set -ps (the supplier); keep lock files in the repository so versions resolve.' }
            if ($copyleft) { & $find $row 'Low' 'Strong copyleft licence' "$copyleft component(s) under GPL, AGPL, SSPL or another strong copyleft licence." 'Check with whoever owns open-source compliance before distributing - strong copyleft can require releasing your source.' }
            if ($components.Count -and $unknown / $components.Count -gt 0.25) { & $find $row 'Info' 'Licences mostly unknown' "$unknown of $($components.Count) components have no licence the SBOM could tell (NOASSERTION)." 'Use sbom-tool''s licence lookup (-li true, on by default in recent versions) or a licence scanner, so licences can be reviewed.' }
            if ($ships -and -not $validated) { & $find $row 'Info' 'SBOM not validated' 'No sbom-tool validate step was found here: nothing checks that what is deployed is what the SBOM lists.' 'Run sbom-tool validate -b <drop> -o <output.json> -mi SPDX:2.2 before deploying (in the release stage or pipeline), and fail on a mismatch.' }
        }
    }

    # --- Licences across the SBOMs ---------------------------------------------------------------------------
    # Per project, so the report's project selector filters them too.
    $licenseRows = @(foreach ($group in $componentRows | Group-Object { "$($_.Project)|$(if ($_.License) { $_.License } else { '(unknown)' })" }) {
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.DevOpsSbomLicense'; Organization = $group.Group[0].Organization; Project = $group.Group[0].Project; License = ($group.Name -split '\|', 2)[1]
                Kind = $group.Group[0].LicenseKind; Components = @($group.Group | ForEach-Object { "$($_.Component)@$($_.Version)" } | Select-Object -Unique).Count
                Pipelines = @($group.Group | ForEach-Object { "$($_.Project)|$($_.Pipeline)" } | Select-Object -Unique).Count
            }
        }) | Sort-Object -Property Project, @{ Expression = { $kindRank[$_.Kind] }; Descending = $true }, @{ Expression = 'Components'; Descending = $true }, License

    $shipping = @($pipelineRows | Where-Object Ships -EQ 'Yes')
    @{
        Pipelines  = $pipelineRows.ToArray()
        Components = $componentRows.ToArray()
        Licenses   = @($licenseRows)
        Findings   = $findings.ToArray()
        Stats      = @{
            SbomPipelines   = $pipelineRows.Count
            SbomGenerating  = @($pipelineRows | Where-Object { $_.Generator }).Count
            SbomShipping    = $shipping.Count
            SbomShippingWithout = @($shipping | Where-Object Status -EQ 'No SBOM').Count
            SbomPublished   = @($pipelineRows | Where-Object Status -EQ 'SBOM published').Count
            SbomComponents  = $componentRows.Count
            SbomCopyleft    = @($componentRows | Where-Object LicenseKind -EQ 'Strong copyleft').Count
        }
    }
}
