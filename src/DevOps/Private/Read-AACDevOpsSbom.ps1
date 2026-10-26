function Read-AACDevOpsSbom {
    <#
    .SYNOPSIS
        Reads the software bill of materials (SBOM) each pipeline's latest
        successful run published - the Microsoft SBOM Tool's
        _manifest/spdx_2.2 (or spdx_3.0) manifest.spdx.json, or any SPDX or
        CycloneDX JSON file - for Invoke-AACADOAssessment's SBOM tab.
    .DESCRIPTION
        Four rounds of parallel requests, each only for what the last one
        found:
          1. each pipeline's latest completed run that succeeded (or
             partially succeeded)
          2. that run's artifacts (-MaxArtifacts at most)
          3. each artifact's file list - a pipeline artifact's manifest, or
             a build (container) artifact's items
          4. the best SBOM file found, by name: spdx_3.0, then spdx_2.2
             manifest.spdx.json, then *.spdx.json, *.cdx.json / bom.json,
             then *sbom*.json
        -Target: @(@{ Key; ProjectId; PipelineId }). Returns Key ->
        @{ Status ('Found', 'Not found', 'No successful run', 'Not read');
        Detail; BuildId; BuildNumber; Finished; Artifact; Path; Document
        (the parsed JSON, or $null) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $OrganizationUrl,

        [Parameter(Mandatory)]
        [string] $Authorization,

        [AllowEmptyCollection()]
        [object[]] $Target = @(),

        [int] $MaxArtifacts = 10,

        [int] $ThrottleLimit = 12,

        # Called with (step, text, done, total).
        [scriptblock] $OnProgress
    )

    $org = $OrganizationUrl.TrimEnd('/')
    $api = 'api-version=7.1'
    $enc = { param([string] $Text) [System.Uri]::EscapeDataString($Text) }
    $result = @{}
    $ask = {
        param([string] $Step, [string] $Text, [System.Collections.IDictionary] $Uris)
        if (-not $Uris.Count) { return @{} }
        if ($OnProgress) { & $OnProgress $Step $Text 0 $Uris.Count }
        $answers = Invoke-AACArmParallel -Uri @($Uris.Values) -Authorization $Authorization -ThrottleLimit $ThrottleLimit -OnProgress {
            param($Done, $Total)
            if ($OnProgress) { & $OnProgress $Step $Text $Done $Total }
        }
        $byKey = @{}
        foreach ($key in $Uris.Keys) { $byKey[$key] = $answers[$Uris[$key]] }
        $byKey
    }
    $failed = { param($Answer) -not $Answer -or [string]$Answer['Error'] }
    $why = { param($Answer) if ($Answer) { [string]$Answer['Error'] } else { 'no answer' } }
    # Which file is the SBOM: the lower, the likelier.
    $rankOf = {
        param([string] $Path)
        switch -Regex ($Path) {
            '(?i)_manifest/spdx_3\.\d+/manifest\.spdx\.json$' { 0; break }
            '(?i)_manifest/spdx_2\.\d+/manifest\.spdx\.json$' { 1; break }
            '(?i)\.spdx\.json$' { 2; break }
            '(?i)(\.cdx\.json|/bom\.json|cyclonedx[^/]*\.json)$' { 3; break }
            '(?i)sbom[^/]*\.json$' { 4; break }
            default { -1 }
        }
    }

    # --- 1. Each pipeline's latest successful run ------------------------------------------------------------
    $byKey = @{}
    $uris = [ordered]@{}
    foreach ($t in $Target) {
        $byKey[$t.Key] = $t
        $result[$t.Key] = @{ Status = 'Not read'; Detail = ''; BuildId = $null; BuildNumber = ''; Finished = $null; Artifact = ''; Path = ''; Document = $null }
        $uris[$t.Key] = "$org/$($t.ProjectId)/_apis/build/builds?definitions=$($t.PipelineId)&statusFilter=completed&resultFilter=succeeded,partiallySucceeded&queryOrder=finishTimeDescending&`$top=1&$api"
    }
    $answers = & $ask 'sbom-runs' 'SBOM: finding each pipeline''s latest successful run' $uris
    $builds = @{}
    foreach ($key in $answers.Keys) {
        $answer = $answers[$key]
        if (& $failed $answer) { $result[$key].Detail = "The runs couldn't be read: $(& $why $answer)"; continue }
        $run = @($answer['Items'] | Where-Object { $_ -and [string](Get-AACMember -InputObject $_ -Path 'definition.id') -eq [string]$byKey[$key].PipelineId -and [string]$_['result'] -in 'succeeded', 'partiallySucceeded' }) | Select-Object -First 1
        if (-not $run) { $result[$key].Status = 'No successful run'; $result[$key].Detail = 'No run succeeded, so there is no SBOM to read.'; continue }
        $result[$key].BuildId = [int]$run['id']
        $result[$key].BuildNumber = [string]$run['buildNumber']
        $result[$key].Finished = [string]$run['finishTime']
        $builds[$key] = [int]$run['id']
    }

    # --- 2. Its artifacts ------------------------------------------------------------------------------------
    $uris = [ordered]@{}
    foreach ($key in $builds.Keys) { $uris[$key] = "$org/$($byKey[$key].ProjectId)/_apis/build/builds/$($builds[$key])/artifacts?$api" }
    $answers = & $ask 'sbom-artifacts' 'SBOM: listing the artifacts of those runs' $uris
    $artifacts = @{}
    foreach ($key in $answers.Keys) {
        $answer = $answers[$key]
        if (& $failed $answer) { $result[$key].Detail = "The run's artifacts couldn't be read: $(& $why $answer)"; continue }
        $items = @($answer['Items'] | Where-Object { $_ } | Select-Object -First $MaxArtifacts)
        if (-not $items.Count) { $result[$key].Status = 'Not found'; $result[$key].Detail = "Run $($result[$key].BuildNumber) published no artifact."; continue }
        $artifacts[$key] = $items
    }

    # --- 3. Each artifact's files ----------------------------------------------------------------------------
    $uris = [ordered]@{}
    $listed = @{}
    foreach ($key in $artifacts.Keys) {
        $i = 0
        foreach ($a in $artifacts[$key]) {
            $name = [string]$a['name']
            $type = [string](Get-AACMember -InputObject $a -Path 'resource.type')
            $data = [string](Get-AACMember -InputObject $a -Path 'resource.data')
            $listKey = "$key|$i"
            $i++
            if ($type -eq 'Container' -and $data -match '^#/(\d+)/') {
                # A build artifact lives in a file container: list its items under the artifact's folder.
                $listed[$listKey] = @{ Key = $key; Name = $name; Kind = 'Container'; Container = $Matches[1] }
                $uris[$listKey] = "$org/_apis/resources/Containers/$($Matches[1])?itemPath=$(& $enc $name)&api-version=7.1-preview.4"
            }
            elseif ($type -eq 'PipelineArtifact' -and $data) {
                # A pipeline artifact: its data names the manifest that lists its files and their blobs.
                $listed[$listKey] = @{ Key = $key; Name = $name; Kind = 'PipelineArtifact' }
                $uris[$listKey] = "$org/$($byKey[$key].ProjectId)/_apis/build/builds/$($builds[$key])/artifacts?artifactName=$(& $enc $name)&fileId=$(& $enc $data)&fileName=$(& $enc $name)&$api"
            }
        }
    }
    $answers = & $ask 'sbom-files' 'SBOM: looking for the SBOM in each artifact' $uris
    $best = @{}
    foreach ($listKey in $answers.Keys) {
        $info = $listed[$listKey]
        $answer = $answers[$listKey]
        if (& $failed $answer) { if (-not $result[$info.Key].Detail) { $result[$info.Key].Detail = "Artifact $($info.Name) couldn't be listed: $(& $why $answer)" }; continue }
        $files = if ($info.Kind -eq 'Container') {
            @($answer['Items'] | Where-Object { $_ -and [string]$_['itemType'] -ne 'folder' } | ForEach-Object { @{ Path = [string]$_['path']; Id = '' } })
        }
        else {
            @(Get-AACMember -InputObject $answer['Body'] -Path 'items') | Where-Object { $_ } | ForEach-Object { @{ Path = [string]$_['path']; Id = [string](Get-AACMember -InputObject $_ -Path 'blob.id') } }
        }
        foreach ($f in $files) {
            $rank = & $rankOf $f.Path
            if ($rank -lt 0) { continue }
            $current = $best[$info.Key]
            if (-not $current -or $rank -lt $current.Rank) { $best[$info.Key] = @{ Rank = $rank; Info = $info; Path = $f.Path; Id = $f.Id } }
        }
    }
    foreach ($key in $artifacts.Keys) {
        if (-not $best.Contains($key) -and $result[$key].Status -eq 'Not read' -and -not $result[$key].Detail) {
            $result[$key].Status = 'Not found'
            $result[$key].Detail = "No SBOM file in the artifacts of run $($result[$key].BuildNumber) ($(@($artifacts[$key] | ForEach-Object { [string]$_['name'] }) -join ', '))."
        }
    }

    # --- 4. The SBOM itself ----------------------------------------------------------------------------------
    $uris = [ordered]@{}
    foreach ($key in $best.Keys) {
        $b = $best[$key]
        $uris[$key] = if ($b.Info.Kind -eq 'Container') {
            "$org/_apis/resources/Containers/$($b.Info.Container)?itemPath=$(& $enc $b.Path)&`$format=OctetStream&api-version=7.1-preview.4"
        }
        else {
            "$org/$($byKey[$key].ProjectId)/_apis/build/builds/$($builds[$key])/artifacts?artifactName=$(& $enc $b.Info.Name)&fileId=$(& $enc $b.Id)&fileName=$(& $enc ($b.Path -replace '^.*/', ''))&$api"
        }
    }
    $answers = & $ask 'sbom-documents' 'SBOM: reading the SBOMs' $uris
    foreach ($key in $answers.Keys) {
        $answer = $answers[$key]
        $result[$key].Artifact = $best[$key].Info.Name
        $result[$key].Path = $best[$key].Path
        if ((& $failed $answer) -or $answer['Body'] -isnot [System.Collections.IDictionary]) { $result[$key].Detail = "The SBOM $($best[$key].Path) couldn't be read: $(& $why $answer)"; continue }
        $result[$key].Status = 'Found'
        $result[$key].Document = $answer['Body']
    }
    $result
}
