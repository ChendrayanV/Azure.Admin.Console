function ConvertTo-AACWafAssessment {
    <#
    .SYNOPSIS
        Evaluates the Well-Architected checks against the shared Resource
        Graph read and scores them - by check, design principle and pillar,
        and by subscription, resource group or resource type for the heat
        maps.
    .DESCRIPTION
        No Azure calls: Invoke-AACWafAssessment reads (Get-AACWafQuery), this
        decides.

        Three sources of checks:
          Catalogue  Get-AACWafCatalog: each check's Test on each resource of
                     its type (or each subscription), pass or fail
          Advisor    one check per pillar (AD-HA, AD-SEC): a resource with an
                     open recommendation fails, the other resources of those
                     types in the same subscription and resource group pass
          Defender   one check (DF-HIGH): a resource with an open
                     high-severity recommendation fails, one with only
                     healthy ones passes
        Duplicates are counted once: an Advisor or Defender item matching an
        overlap (Get-AACWafCatalog's Overlaps) on a resource the catalogue
        check tested is dropped from its folded check, and the catalogue
        result's Detail says 'Also flagged by Advisor: ...'. -KeepDuplicates
        keeps every item.

        Scores are 0-100: a check's is the share of resources that pass; a
        group of checks' is their scores weighted by severity (High 3,
        Medium 2, Low 1), over the checks with anything to test.

        Returns @{
          Results     AAC.WafCheckResult, one per check and resource (Advisor
                      passes are counted, not listed; Detail names the open
                      Advisor and Defender items)
          Checks      AAC.WafCheck: per check - evaluated, passed, failed, score
          Principles  AAC.WafPrincipleScore: every principle, assessed or not
          Pillars     AAC.WafPillarScore
          HeatMaps    two report heat maps: pillars and principles by
                      -HeatMapBy
          Overall     the mean of the pillar scores (or $null)
          Stats       counts
        }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Invoke-AACGraphBatch's Rows, by query name.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Read,

        # Get-AACWafCatalog's result.
        [Parameter(Mandatory)]
        [hashtable] $Catalog,

        [ValidateSet('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')]
        [string[]] $Pillar = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency'),

        # Subscription ID (lower case) -> name: the subscriptions in scope.
        [hashtable] $SubscriptionName = @{},

        [ValidateSet('Subscription', 'ResourceGroup', 'ResourceType')]
        [string] $HeatMapBy = 'Subscription',

        [string[]] $ExcludeCheck = @(),

        # Tag names that allocate cost, and that name an owner.
        [string[]] $CostTag = @('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode'),

        [string[]] $OwnerTag = @('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner'),

        # Answers from the questionnaire (Read-AACWafAttestation): @{ Pillar;
        # Principle; Question; Answer (Yes, Partly, No); Evidence; Owner }.
        [AllowEmptyCollection()]
        [object[]] $Attestation = @(),

        [datetime] $Now = [datetime]::UtcNow,

        # Count Advisor and Defender items a catalogue check already tested.
        [switch] $KeepDuplicates
    )

    $at = {
        param($Row, [string[]] $Keys)
        $value = $Row
        foreach ($key in $Keys) {
            if ($value -isnot [System.Collections.IDictionary]) { return $null }
            if ($value.Contains($key)) { $value = $value[$key]; continue }
            $found = $null
            foreach ($name in $value.Keys) { if ($name -eq $key) { $found = $value[$name]; break } }
            $value = $found
        }
        $value
    }
    $rows = { param([string] $Name) @(if ($Read.Contains($Name)) { $Read[$Name] | Where-Object { $null -ne $_ } }) }
    $weight = @{ High = 3; Medium = 2; Low = 1 }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $shortType = { param([string] $Type) $parts = $Type -split '/'; if ($parts.Count -ge 2) { "$(($parts[0] -replace '^microsoft\.', ''))/$($parts[1..($parts.Count - 1)] -join '/')" } else { $Type } }
    $column = {
        param([string] $Subscription, [string] $Group, [string] $Type)
        switch ($HeatMapBy) {
            'ResourceGroup' { if ($Group) { "$Group ($(& $subName $Subscription))" } else { "(subscription) $(& $subName $Subscription)" } }
            'ResourceType' { & $shortType $Type }
            default { & $subName $Subscription }
        }
    }
    $excluded = { param([string] $Id) @($ExcludeCheck | Where-Object { $Id -like $_ }).Count -gt 0 }
    $inScope = { param([string] $Subscription) -not $SubscriptionName.Count -or $SubscriptionName.Contains($Subscription) }

    # The context the checks read.
    $backup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($b in & $rows 'backup') { [void]$backup.Add([string]$b['id']) }
    $pricing = @{}
    foreach ($p in & $rows 'pricing') {
        $sub = [string]$p['subscriptionId']
        if (-not $pricing.Contains($sub)) { $pricing[$sub] = @{} }
        $pricing[$sub][[string]$p['name']] = [string]$p['tier']
    }
    $secureScore = @{}
    foreach ($s in & $rows 'secureScore') { if ([double]$s['max'] -gt 0) { $secureScore[[string]$s['subscriptionId']] = [Math]::Round(100 * [double]$s['current'] / [double]$s['max'], 1) } }
    $extensions = @{}
    foreach ($e in & $rows 'extensions') {
        $vm = [string]$e['vm']
        if (-not $extensions.Contains($vm)) { $extensions[$vm] = [System.Collections.Generic.List[string]]::new() }
        $extensions[$vm].Add([string]$e['extension'])
    }
    $autoscale = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($a in & $rows 'autoscale') { [void]$autoscale.Add([string]$a['target']) }
    $slots = @{}
    foreach ($sl in & $rows 'slots') { $site = [string]$sl['site']; $slots[$site] = 1 + $(if ($slots.Contains($site)) { $slots[$site] } else { 0 }) }
    $typeCount = @{}
    foreach ($i in & $rows 'inventory') {
        $sub = [string]$i['subscriptionId']
        if (-not $typeCount.Contains($sub)) { $typeCount[$sub] = @{} }
        $typeCount[$sub][[string]$i['type']] = [int]$i['n'] + $(if ($typeCount[$sub].Contains([string]$i['type'])) { $typeCount[$sub][[string]$i['type']] } else { 0 })
    }
    $context = @{ At = $at; Backup = $backup; Pricing = $pricing; SecureScore = $secureScore; Extensions = $extensions; Autoscale = $autoscale; Slots = $slots; TypeCount = $typeCount; CostTag = $CostTag; OwnerTag = $OwnerTag; Now = $Now }

    # --- Checks and their results -------------------------------------------------------------------------------
    $checks = [ordered]@{}
    $results = [System.Collections.Generic.List[object]]::new()
    # Counts per check and heat-map cell: check id -> column -> @{ Passed; Failed }.
    $tally = @{}
    $count = {
        param([string] $CheckId, [string] $Column, [int] $Passed, [int] $Failed)
        if (-not $tally.Contains($CheckId)) { $tally[$CheckId] = @{} }
        if (-not $tally[$CheckId].Contains($Column)) { $tally[$CheckId][$Column] = @{ Passed = 0; Failed = 0 } }
        $tally[$CheckId][$Column].Passed += $Passed
        $tally[$CheckId][$Column].Failed += $Failed
    }
    $addCheck = {
        param([string] $Id, [string] $PillarName, [string] $Principle, [string] $Title, [string] $Severity, [string] $Source, [string] $Recommendation, [string] $Link)
        if (-not $checks.Contains($Id)) { $checks[$Id] = @{ Id = $Id; Pillar = $PillarName; Principle = $Principle; Title = $Title; Severity = $Severity; Source = $Source; Recommendation = $Recommendation; Link = $Link } }
    }
    $addResult = {
        param($Check, [string] $Status, [string] $Name, [string] $Type, [string] $Subscription, [string] $Group, [string] $Id, [string] $Detail, [string] $Cell)
        $cell = if ($Cell) { $Cell } else { & $column $Subscription $Group $Type }
        & $count $Check.Id $cell $(if ($Status -eq 'Pass') { 1 } else { 0 }) $(if ($Status -eq 'Fail') { 1 } else { 0 })
        $results.Add([pscustomobject][ordered]@{
                PSTypeName     = 'AAC.WafCheckResult'
                Pillar         = $Check.Pillar
                Principle      = $Check.Principle
                CheckId        = $Check.Id
                Check          = $Check.Title
                Severity       = $Check.Severity
                Status         = $Status
                Resource       = $Name
                ResourceType   = $Type
                ResourceGroup  = $Group
                Subscription   = & $subName $Subscription
                HeatColumn     = $cell
                Source         = $Check.Source
                Detail         = $Detail
                Recommendation = $Check.Recommendation
                Link           = $Check.Link
                ResourceId     = $Id
            })
    }

    # Catalogue.
    $byType = @{}
    foreach ($r in @(& $rows 'resources') + @(& $rows 'groups')) {
        if (-not (& $inScope ([string]$r['subscriptionId']))) { continue }
        $t = [string]$r['type']
        if (-not $byType.Contains($t)) { $byType[$t] = [System.Collections.Generic.List[object]]::new() }
        $byType[$t].Add($r)
    }
    $subjects = @(foreach ($sub in @($SubscriptionName.Keys | Sort-Object)) { @{ id = "/subscriptions/$sub"; name = & $subName $sub; type = 'microsoft.resources/subscriptions'; subscriptionId = $sub; resourceGroup = '' } })
    foreach ($c in @($Catalog.Checks | Where-Object { $_.Pillar -in $Pillar -and -not (& $excluded $_.Id) })) {
        & $addCheck $c.Id $c.Pillar $c.Principle $c.Title $c.Severity 'Catalogue' $c.Recommendation $c.Link
        $targets = if ($c.Type -eq 'microsoft.resources/subscriptions') { $subjects } elseif ($byType.Contains($c.Type)) { @($byType[$c.Type]) } else { @() }
        foreach ($r in $targets) {
            if ($c.Applies -and -not (& $c.Applies $r $context)) { continue }
            $passed = [bool](& $c.Test $r $context)
            & $addResult $checks[$c.Id] $(if ($passed) { 'Pass' } else { 'Fail' }) ([string]$r['name']) $c.Type ([string]$r['subscriptionId']) ([string]$r['resourceGroup']) ([string]$r['id']) ''
        }
    }

    # Advisor and Defender each fold into one check per pillar, scored per
    # resource: a tenant has hundreds of recommendation types (Defender's
    # per-package vulnerabilities alone run to hundreds), and a check each
    # would drown the catalogue. A resource fails when it has any open item;
    # the detail names them.
    $typeOf = { param([string] $Id) if ($Id -match '/providers/([^/]+/[^/]+)/') { $Matches[1].ToLowerInvariant() } elseif ($Id -match '^/subscriptions/[^/]+$') { 'microsoft.resources/subscriptions' } else { '' } }
    $summary = { param([string[]] $Items) $unique = @($Items | Where-Object { $_ } | Select-Object -Unique); (($unique | Select-Object -First 3) -join '; ') + $(if ($unique.Count -gt 3) { "; +$($unique.Count - 3) more" }) }
    # What the catalogue tested, by check and resource: an Advisor or Defender
    # item that matches an overlap there is the same finding, counted once.
    $tested = @{}
    foreach ($r in $results) { $tested["$($r.CheckId)|$(([string]$r.ResourceId).ToLowerInvariant())"] = $r }
    $duplicates = @{ Count = 0 }
    $dedupe = {
        param([object[]] $Items, [string] $Source)
        if ($KeepDuplicates) { return $Items }
        foreach ($item in $Items) {
            $same = $null
            foreach ($o in @($Catalog.Overlaps)) {
                if ($item.Text -notmatch "(?i)$($o.Pattern)") { continue }
                foreach ($checkId in $o.Checks) { $key = "$checkId|$(([string]$item.Id).ToLowerInvariant())"; if ($tested.Contains($key)) { $same = $tested[$key]; break } }
                if ($same) { break }
            }
            if (-not $same) { $item; continue }
            $duplicates.Count++
            if (-not $item.Healthy) {
                $note = "Also flagged by $($Source): $($item.Text)"
                $same.Detail = if ($same.Detail) { "$($same.Detail); $note" } else { $note }
            }
        }
    }
    $folded = {
        # $Items: @{ Id; Type; Subscription; Group; Text; Healthy } - one per item, many per resource.
        param($Check, [object[]] $Items)
        foreach ($resource in @($Items | Group-Object -Property Id)) {
            $first = $resource.Group[0]
            $open = @($resource.Group | Where-Object { -not $_.Healthy })
            & $addResult $Check $(if ($open.Count) { 'Fail' } else { 'Pass' }) (($first.Id -split '/')[-1]) $first.Type $first.Subscription $first.Group $first.Id $(if ($open.Count) { "$($open.Count) open: $(& $summary @($open | ForEach-Object { $_.Text }))" } else { '' })
        }
    }

    $inventory = @{}
    foreach ($i in & $rows 'inventory') { $inventory["$($i['type'])|$($i['subscriptionId'])|$(([string]$i['resourceGroup']).ToLowerInvariant())"] = [int]$i['n'] }
    $advisorChecks = @{
        HighAvailability = @{ Id = 'AD-HA'; Pillar = 'Reliability'; Principle = 'Design for resilience'; Title = 'No open Advisor reliability recommendations' }
        Security         = @{ Id = 'AD-SEC'; Pillar = 'Security'; Principle = 'Sustain and evolve your security posture'; Title = 'No open Advisor security recommendations' }
        Cost             = @{ Id = 'AD-COST'; Pillar = 'Cost Optimization'; Principle = 'Monitor and optimize over time'; Title = 'No open Advisor cost recommendations' }
        OperationalExcellence = @{ Id = 'AD-OPS'; Pillar = 'Operational Excellence'; Principle = 'Establish development standards'; Title = 'No open Advisor operational excellence recommendations' }
        Performance      = @{ Id = 'AD-PERF'; Pillar = 'Performance Efficiency'; Principle = 'Improve efficiency through optimization'; Title = 'No open Advisor performance recommendations' }
    }
    foreach ($category in @($advisorChecks.Keys)) {
        $spec = $advisorChecks[$category]
        if ($spec.Pillar -notin $Pillar -or (& $excluded $spec.Id)) { continue }
        $items = @(foreach ($a in & $rows 'advisor') {
                if ([string]$a['category'] -ne $category -or -not (& $inScope ([string]$a['subscriptionId']))) { continue }
                $id = [string]$a['resourceId']
                @{ Id = $id; Type = $(if ($a['impactedType']) { [string]$a['impactedType'] } else { & $typeOf $id }); Subscription = [string]$a['subscriptionId']; Group = [string]$a['resourceGroup']; Text = "$($a['problem']) ($($a['impact']))"; Healthy = $false }
            })
        $items = @(& $dedupe $items 'Advisor')
        if (-not $items.Count) { continue }
        & $addCheck $spec.Id $spec.Pillar $spec.Principle $spec.Title 'High' 'Advisor' 'Work through the open Advisor recommendations on these resources (Azure portal > Advisor), highest impact first.' 'https://learn.microsoft.com/azure/advisor/advisor-overview'
        & $folded $checks[$spec.Id] $items
        # The other resources of those types, in the same subscription and resource group, pass.
        foreach ($bucket in @($items | Group-Object -Property { "$($_.Type)|$($_.Subscription)|$($_.Group.ToLowerInvariant())" })) {
            $flagged = @($bucket.Group | ForEach-Object { $_.Id } | Select-Object -Unique).Count
            $total = if ($inventory.Contains($bucket.Name)) { $inventory[$bucket.Name] } else { $flagged }
            $first = $bucket.Group[0]
            $passed = [Math]::Max(0, $total - $flagged)
            if ($passed) { & $count $spec.Id (& $column $first.Subscription $first.Group $first.Type) $passed 0 }
        }
    }

    $defenderId = 'DF-HIGH'
    if ('Security' -in $Pillar -and -not (& $excluded $defenderId)) {
        $items = @(foreach ($a in & $rows 'assessments') {
                if (-not (& $inScope ([string]$a['subscriptionId']))) { continue }
                $id = [string]$a['resourceId']
                @{ Id = $id; Type = & $typeOf $id; Subscription = [string]$a['subscriptionId']; Group = [string]$a['resourceGroup']; Text = [string]$a['name']; Healthy = [string]$a['status'] -eq 'Healthy' }
            })
        $items = @(& $dedupe $items 'Defender')
        if ($items.Count) {
            & $addCheck $defenderId 'Security' 'Sustain and evolve your security posture' 'No open high-severity Defender for Cloud recommendations' 'High' 'Defender' 'Remediate the open high-severity recommendations on these resources (Defender for Cloud > Recommendations).' 'https://learn.microsoft.com/azure/defender-for-cloud/review-security-recommendations'
            & $folded $checks[$defenderId] $items
        }
    }

    # Attestation: a person's answer for a principle no API can test. Yes
    # passes, No fails, Partly counts as half; its heat-map column is 'Attested'.
    $abbreviation = @{ Reliability = 'RE'; Security = 'SE'; 'Cost Optimization' = 'CO'; 'Operational Excellence' = 'OE'; 'Performance Efficiency' = 'PE' }
    foreach ($a in $Attestation) {
        $pillarName = [string]$a.Pillar
        $answer = [string]$a.Answer
        if ($pillarName -notin $Pillar -or $answer -notin 'Yes', 'Partly', 'No') { continue }
        $index = [array]::IndexOf(@($Catalog.Principles[$pillarName] | ForEach-Object { $_.Name }), [string]$a.Principle) + 1
        if ($index -lt 1) { continue }
        $id = "AT-$($abbreviation[$pillarName])-$index"
        if (& $excluded $id) { continue }
        & $addCheck $id $pillarName ([string]$a.Principle) ([string]$a.Question) 'Medium' 'Attestation' 'Close the gap the answer describes, then update the questionnaire.' (@($Catalog.Principles[$pillarName] | Where-Object { $_.Name -eq $a.Principle })[0].Link)
        $detail = (@(if ($a.Evidence) { "Evidence: $($a.Evidence)" }; if ($a.Owner) { "Owner: $($a.Owner)" }) -join ' · ')
        & $addResult $checks[$id] $(if ($answer -eq 'Yes') { 'Pass' } elseif ($answer -eq 'No') { 'Fail' } else { 'Partly' }) 'Workload (attested)' 'attestation' '' '' "attestation:$id" $detail 'Attested'
        if ($answer -eq 'Partly') { & $count $id 'Attested' 1 1 }
    }

    # --- Scores -------------------------------------------------------------------------------------------------
    $rate = { param([int] $Passed, [int] $Failed) if ($Passed + $Failed) { 100.0 * $Passed / ($Passed + $Failed) } else { $null } }
    # A group of checks' score in one heat-map cell (or all cells with $Column = $null).
    $score = {
        param([string[]] $CheckIds, $Column)
        $sum = 0.0; $weights = 0; $evaluated = 0; $failed = 0
        foreach ($id in $CheckIds) {
            if (-not $tally.Contains($id)) { continue }
            $p = 0; $f = 0
            foreach ($cell in @($tally[$id].Keys)) { if ($null -eq $Column -or $cell -eq $Column) { $p += $tally[$id][$cell].Passed; $f += $tally[$id][$cell].Failed } }
            if (-not ($p + $f)) { continue }
            $w = $weight[$checks[$id].Severity]
            $sum += $w * (& $rate $p $f); $weights += $w; $evaluated += $p + $f; $failed += $f
        }
        if ($weights) { @{ Score = [Math]::Round($sum / $weights, 1); Count = $evaluated; Failed = $failed } } else { $null }
    }

    $checkRows = @(foreach ($c in $checks.Values) {
            $p = 0; $f = 0
            if ($tally.Contains($c.Id)) { foreach ($cell in $tally[$c.Id].Values) { $p += $cell.Passed; $f += $cell.Failed } }
            $s = & $rate $p $f
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.WafCheck'; Pillar = $c.Pillar; Principle = $c.Principle; CheckId = $c.Id; Check = $c.Title; Severity = $c.Severity; Source = $c.Source
                Evaluated = $p + $f; Passed = $p; Failed = $f; Score = $(if ($null -ne $s) { [Math]::Round($s, 1) } else { $null })
                Status = $(if (-not ($p + $f)) { 'Not assessed' } elseif ($f) { 'Gaps' } else { 'Pass' })
                Recommendation = $c.Recommendation; Link = $c.Link
            }
        })
    $columns = @($results | Group-Object -Property HeatColumn | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | ForEach-Object { $_.Name })
    $principleRows = [System.Collections.Generic.List[object]]::new()
    $heatPrinciples = [System.Collections.Generic.List[object]]::new()
    $heatPillars = [System.Collections.Generic.List[object]]::new()
    $pillarRows = [System.Collections.Generic.List[object]]::new()
    foreach ($pillarName in @($Catalog.Principles.Keys | Where-Object { $_ -in $Pillar })) {
        $pillarIds = @($checks.Values | Where-Object { $_.Pillar -eq $pillarName } | ForEach-Object { $_.Id })
        $total = & $score $pillarIds $null
        foreach ($principle in $Catalog.Principles[$pillarName]) {
            $ids = @($checks.Values | Where-Object { $_.Pillar -eq $pillarName -and $_.Principle -eq $principle.Name } | ForEach-Object { $_.Id })
            $all = & $score $ids $null
            $principleRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.WafPrincipleScore'; Pillar = $pillarName; Principle = $principle.Name
                    Score = $(if ($all) { $all.Score } else { $null }); Checks = $ids.Count; Evaluated = $(if ($all) { $all.Count } else { 0 }); Failed = $(if ($all) { $all.Failed } else { 0 })
                    Coverage = $(if (-not $all) { 'Not assessed - needs a review or attestation' } else {
                            $sources = @($ids | Where-Object { $tally.Contains($_) } | ForEach-Object { $checks[$_].Source } | Select-Object -Unique)
                            if ($sources -contains 'Attestation' -and $sources.Count -gt 1) { 'Automated and attested' } elseif ($sources -contains 'Attestation') { 'Attested' } else { 'Automated' }
                        }); Link = $principle.Link
                })
            $heatPrinciples.Add(@{ Label = $principle.Name; Group = $pillarName; Filter = $principle.Name; Cells = @(foreach ($col in $columns) { & $score $ids $col }); Total = $all })
        }
        $heatPillars.Add(@{ Label = $pillarName; Filter = $pillarName; Cells = @(foreach ($col in $columns) { & $score $pillarIds $col }); Total = $total })
        $assessed = @($principleRows | Where-Object { $_.Pillar -eq $pillarName -and $null -ne $_.Score }).Count
        $pillarRows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.WafPillarScore'; Pillar = $pillarName; Score = $(if ($total) { $total.Score } else { $null })
                Maturity = $(if (-not $total) { 'Not assessed' } elseif ($total.Score -ge 90) { 'Optimised' } elseif ($total.Score -ge 75) { 'Established' } elseif ($total.Score -ge 50) { 'Developing' } else { 'Initial' })
                Principles = "$assessed of $(@($Catalog.Principles[$pillarName]).Count) assessed"; Checks = $pillarIds.Count
                Evaluated = $(if ($total) { $total.Count } else { 0 }); Failed = $(if ($total) { $total.Failed } else { 0 })
            })
    }
    $scored = @($pillarRows | Where-Object { $null -ne $_.Score })
    $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1) } else { $null }
    $by = @{ Subscription = 'Subscription'; ResourceGroup = 'Resource group'; ResourceType = 'Resource type' }[$HeatMapBy]
    $failedResults = @($results | Where-Object Status -In 'Fail', 'Partly')
    @{
        Results    = $results.ToArray()
        Checks     = $checkRows
        Principles = $principleRows.ToArray()
        Pillars    = $pillarRows.ToArray()
        Overall    = $overall
        HeatMaps   = @(
            @{ Title = "Pillars by $($by.ToLowerInvariant())"; RowHeader = 'Pillar'; Columns = $columns; Rows = $heatPillars.ToArray(); Table = 'findings'; RowKey = 'Pillar'; ColumnKey = 'HeatColumn'
                Note = 'Each cell: the pillar''s score there, its checks weighted by severity. Click a cell for its findings.' }
            @{ Title = "Design principles by $($by.ToLowerInvariant())"; RowHeader = 'Design principle'; Columns = $columns; Rows = $heatPrinciples.ToArray(); Table = 'findings'; RowKey = 'Principle'; ColumnKey = 'HeatColumn'
                Note = 'A row of - is a principle no check covers yet: it needs a review or attestation.' }
        )
        Stats      = @{
            Checks    = $checkRows.Count
            Assessed  = @($checkRows | Where-Object { $_.Evaluated }).Count
            WithGaps  = @($checkRows | Where-Object { $_.Failed }).Count
            Results   = $results.Count
            Failed    = $failedResults.Count
            High      = @($failedResults | Where-Object Severity -EQ 'High').Count
            Resources = @($results | ForEach-Object { $_.ResourceId } | Select-Object -Unique).Count
            Columns   = $columns.Count
            Duplicates = $duplicates.Count
        }
    }
}
