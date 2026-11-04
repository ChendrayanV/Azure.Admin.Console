function ConvertTo-AACLandingZoneAssessment {
    <#
    .SYNOPSIS
        Rates the Azure Landing Zone checklist against Resource Graph's answers, for
        Invoke-AACLandingZoneAssessment.
    .DESCRIPTION
        No Azure calls. -Item is the checklist (Get-AACServiceBaseline -Set
        LandingZone), and -Read is Invoke-AACGraphBatch's result, by each item's Guid.
        Every query returns a compliant column, but they don't all measure the same
        thing, so a status says what the evidence can bear:

          Fail         the query found something that doesn't comply
          Review       as Fail, but it judged by a name (a management group whose name
                       has 'sandbox' in it, say), which proves little: look at it
          Pass         it found things, and all comply
          Present      the query only looks for a resource and calls it compliant when
                       it is there, so it can't fail. It is there
          No evidence  nothing came back: the resource isn't used, or isn't needed.
                       Neither a pass nor a fail
          Manual       Resource Graph can't answer this one; the reason says why
          Not checked  the query failed

        Fail and Review are findings; Review's severity is Info, as a heuristic
        shouldn't raise the counts. Returns @{ Checks (AAC.LandingZoneCheck); Items
        (AAC.LandingZoneItemResult: what each query found not to comply); Findings;
        Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Item,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    $items = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $errors = 0
    $firstError = ''
    foreach ($entry in $Item) {
        $byName = $entry.Query -match "(displayName|name|mgChain)[A-Za-z]*\s+(has|contains|startswith|matches|=~)|has_any|has\s+'"
        $constant = $entry.Query -match 'extend\s+compliant\s*=\s*1\s*(\||$)'
        $evidence = if (-not $entry.Queryable) { 'None' } elseif ($constant) { 'Presence only' } elseif ($byName) { 'By name' } else { 'Measured' }
        $rows = @()
        $status = 'Manual'
        $detail = $entry.Reason
        if ($entry.Queryable) {
            if ($Read.Errors -and $Read.Errors.Contains($entry.Guid)) {
                $status = 'Not checked'
                $detail = "The query failed: $($Read.Errors[$entry.Guid] -replace '\s+', ' ')"
                $errors++
                if (-not $firstError) { $firstError = $Read.Errors[$entry.Guid] -replace '\s+', ' ' }
            }
            else {
                $rows = @(if ($Read.Rows -and $Read.Rows.Contains($entry.Guid)) { $Read.Rows[$entry.Guid] | Where-Object { $null -ne $_ } })
                $bad = @($rows | Where-Object { [string]$_['compliant'] -in '0', 'False', 'false' })
                $status = if ($bad.Count) { if ($byName) { 'Review' } else { 'Fail' } } elseif ($rows.Count) { if ($constant) { 'Present' } else { 'Pass' } } else { 'No evidence' }
                $detail = switch ($status) {
                    'Fail' { "$($bad.Count) of $($rows.Count) don't comply." }
                    'Review' { "$($bad.Count) of $($rows.Count) don't comply, judged by name only." }
                    'Pass' { "$($rows.Count) checked, all comply." }
                    'Present' { "$($rows.Count) found. This query can't tell more than that." }
                    default { 'Nothing found to judge.' }
                }
                foreach ($row in $bad) {
                    $items.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.LandingZoneItemResult'; Status = $status; Severity = $entry.Severity; Category = $entry.Category; Check = $entry.Name; Name = [string]$row['name']; ResourceId = [string]$row['id']; Guid = $entry.Guid })
                }
                if ($bad.Count) {
                    $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.LandingZoneFinding'; Severity = $(if ($status -eq 'Review') { 'Info' } else { $entry.Severity }); Status = $status; Category = $entry.Category; Check = $entry.Name; Affected = $bad.Count; Detail = $detail; Recommendation = $entry.Name; Guid = $entry.Guid })
                }
            }
        }
        $checks.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.LandingZoneCheck'; Status = $status; Severity = $entry.Severity; Category = $entry.Category; Subcategory = $entry.Subcategory; Check = $entry.Name; Evidence = $evidence; Affected = @($items | Where-Object Guid -EQ $entry.Guid).Count; Detail = $detail; Guid = $entry.Guid })
    }
    $rank = @{ Fail = 0; Review = 1; 'Not checked' = 2; 'No evidence' = 3; Present = 4; Pass = 5; Manual = 6 }
    $severity = @{ High = 0; Medium = 1; Low = 2 }
    @{
        Checks   = @($checks | Sort-Object -Property @{ Expression = { $rank[$_.Status] } }, @{ Expression = { $severity[$_.Severity] } }, Category, Check)
        Items    = $items.ToArray()
        Findings = @($findings | Sort-Object -Property @{ Expression = { $severity[$_.Severity] } }, Category, Check)
        Notices  = @(if ($errors) { "$errors query(ies) failed, so those checks say Not checked: $firstError" })
    }
}
