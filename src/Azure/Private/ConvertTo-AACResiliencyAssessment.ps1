function ConvertTo-AACResiliencyAssessment {
    <#
    .SYNOPSIS
        Rates the Azure Proactive Resiliency Library's recommendations against the
        estate, for Invoke-AACResiliencyAssessment.
    .DESCRIPTION
        No Azure calls. -Recommendation is Get-AACServiceBaseline -Set Resiliency's
        rows, -Present the resource types in scope (lower case -> how many), and -Read
        Invoke-AACGraphBatch's result, by each recommendation's Guid.

        APRL's queries list the resources that don't follow the recommendation, so:

          Fail            it listed resources
          Pass            there are resources of the type, and it listed none
          Manual          the type is in use, but APRL has no query for this. About
                          half have none: this is not a pass, and needs a person
          Not checked     the query failed

        Recommendations for a type that isn't in use aren't returned. Returns @{ Checks
        (AAC.ResiliencyCheck); Items (AAC.ResiliencyItemResult: each resource); Findings
        (AAC.ResiliencyFinding, one per failed recommendation); Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Recommendation,

        [Parameter(Mandatory)]
        [hashtable] $Present,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $errors = 0
    $firstError = ''
    foreach ($entry in $Recommendation) {
        $type = $entry.ResourceType.ToLowerInvariant()
        if (-not $Present.Contains($type)) { continue }
        $status = 'Manual'
        $affected = 0
        $detail = 'APRL has no query for this, so it needs a person to check it.'
        if ($entry.Query) {
            if ($Read.Errors -and $Read.Errors.Contains($entry.Guid)) {
                $status = 'Not checked'
                $detail = "The query failed: $($Read.Errors[$entry.Guid] -replace '\s+', ' ')"
                $errors++
                if (-not $firstError) { $firstError = $Read.Errors[$entry.Guid] -replace '\s+', ' ' }
            }
            else {
                $rows = @(if ($Read.Rows -and $Read.Rows.Contains($entry.Guid)) { $Read.Rows[$entry.Guid] | Where-Object { $null -ne $_ } })
                $affected = $rows.Count
                $status = if ($affected) { 'Fail' } else { 'Pass' }
                $detail = if ($affected) { "$affected of $($Present[$type]) don't follow it." } else { "None of $($Present[$type]) were listed." }
                foreach ($row in $rows) {
                    $items.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ResiliencyItemResult'; Status = $status; Impact = $entry.Impact; Severity = $entry.Impact; ResourceType = $entry.ResourceType; Check = $entry.Name; Name = [string]$row['name']; ResourceId = [string]$row['id']; Param1 = [string]$row['param1']; Param2 = [string]$row['param2']; Guid = $entry.Guid })
                }
                if ($affected) {
                    $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ResiliencyFinding'; Severity = $entry.Impact; ResourceType = $entry.ResourceType; Check = $entry.Name; Category = $entry.Control; Affected = $affected; Detail = $detail; Recommendation = $entry.Benefit; Link = $entry.Link; Guid = $entry.Guid })
                }
            }
        }
        $checks.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ResiliencyCheck'; Status = $status; Severity = $entry.Impact; ResourceType = $entry.ResourceType; Category = $entry.Control; Check = $entry.Name; Evidence = $(if ($entry.Query) { 'APRL query' } else { 'None' }); Affected = $affected; Detail = $detail; Link = $entry.Link; Guid = $entry.Guid })
    }
    $rank = @{ Fail = 0; 'Not checked' = 1; Manual = 2; Pass = 3 }
    $severity = @{ High = 0; Medium = 1; Low = 2 }
    @{
        Checks   = @($checks | Sort-Object -Property @{ Expression = { $rank[$_.Status] } }, @{ Expression = { $severity[$_.Severity] } }, ResourceType, Check)
        Items    = $items.ToArray()
        Findings = @($findings | Sort-Object -Property @{ Expression = { $severity[$_.Severity] } }, ResourceType, Check)
        Notices  = @(if ($errors) { "$errors query(ies) failed, so those checks say Not checked: $firstError" })
    }
}
