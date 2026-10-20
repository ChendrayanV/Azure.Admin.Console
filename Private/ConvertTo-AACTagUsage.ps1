function ConvertTo-AACTagUsage {
    <#
    .SYNOPSIS
        Builds Get-AACTagUsage's list (AAC.TagUsage) from the Resource Graph
        rows of Get-AACTagUsageQuery: each tag name, where it is used, its
        values, and what is inconsistent about it.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result;
        -RequiredTag the tag names that should be everywhere (each gets a
        row, used or not, with its coverage).

        Each tag name as spelled (AAC.TagUsage): its uses on resources,
        resource groups and subscriptions, coverage (the share of resources
        that carry it), distinct values and a sample, and findings:
          Medium  the same name in other casing ('Environment',
                  'environment') - Azure treats tag names case-
                  insensitively, so these collide in cost reports and
                  policies; a required tag on too few resources
          Low     near-duplicates (the same name once spaces, dashes and
                  underscores are ignored: 'cost-center', 'CostCenter');
                  the same value in different casing ('Prod', 'prod')
          Info    a tag used once (a typo?)
        Returns @{ Tags; Totals; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [string[]] $RequiredTag = @(),

        [ValidateRange(1, 100)]
        [int] $CoverageTarget = 90
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $number = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v -or '' -eq $v) { 0 } else { [int64]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(@{ resourceTags = 'resource tags'; groupTags = 'resource group tags'; subscriptionTags = 'subscription tags'; totals = 'totals' }[$key]) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }

    $totals = @{ resources = 0; resourceGroups = 0; subscriptions = 0 }
    $tagged = @{ resources = 0; resourceGroups = 0; subscriptions = 0 }
    foreach ($row in (& $rowsOf 'totals')) { $k = & $text $row 'kind'; if ($totals.Contains($k)) { $totals[$k] = & $number $row 'total'; $tagged[$k] = & $number $row 'tagged' } }

    # Tag names as spelled, with their use in each place.
    $ordinal = [System.StringComparer]::Ordinal
    $byName = [System.Collections.Generic.Dictionary[string, hashtable]]::new($ordinal)
    foreach ($pair in @(@('resourceTags', 'Resources'), @('groupTags', 'ResourceGroups'), @('subscriptionTags', 'Subscriptions'))) {
        foreach ($row in (& $rowsOf $pair[0])) {
            $name = & $text $row 'name'
            if (-not $name) { continue }
            if (-not $byName.ContainsKey($name)) { $byName[$name] = @{ Resources = 0; ResourceGroups = 0; Subscriptions = 0; Values = [System.Collections.Generic.HashSet[string]]::new($ordinal); ValueCount = 0 } }
            $entry = $byName[$name]
            $entry[$pair[1]] = & $number $row 'uses'
            $entry.ValueCount = [Math]::Max($entry.ValueCount, (& $number $row 'valueCount'))
            foreach ($v in @(& $list (& $get $row 'values'))) { [void]$entry.Values.Add([string]$v) }
        }
    }
    foreach ($required in @($RequiredTag | Where-Object { $_ })) {
        if (-not @($byName.Keys | Where-Object { $_ -eq $required }).Count) {
            $byName[$required] = @{ Resources = 0; ResourceGroups = 0; Subscriptions = 0; Values = [System.Collections.Generic.HashSet[string]]::new($ordinal); ValueCount = 0 }
        }
    }

    $normal = { param([string] $Name) ($Name.ToLowerInvariant() -replace '[\s_\-\.]', '') }
    $rank = (Get-AACSeverityRank).Rank
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @($byName.Keys)) {
        $e = $byName[$name]
        $findings = [System.Collections.Generic.List[object]]::new()
        $sameIgnoringCase = @($byName.Keys | Where-Object { $_ -cne $name -and $_.ToLowerInvariant() -eq $name.ToLowerInvariant() })
        $near = @($byName.Keys | Where-Object { $_.ToLowerInvariant() -ne $name.ToLowerInvariant() -and (& $normal $_) -eq (& $normal $name) })
        if ($sameIgnoringCase.Count) { $findings.Add(@{ S = 'Medium'; T = "Also spelled $(($sameIgnoringCase | ForEach-Object { "'$_'" }) -join ', ') - tag names are case-insensitive in Azure, so these collide in cost reports and policies; settle on one." }) }
        if ($near.Count) { $findings.Add(@{ S = 'Low'; T = "Near-duplicate of $(($near | ForEach-Object { "'$_'" }) -join ', ') - pick one name." }) }
        $valueGroups = @($e.Values | Group-Object { $_.ToLowerInvariant() } | Where-Object { @($_.Group | Select-Object -Unique).Count -gt 1 })
        if ($valueGroups.Count) { $findings.Add(@{ S = 'Low'; T = "Values differ only in casing: $((@($valueGroups | Select-Object -First 3 | ForEach-Object { ($_.Group | Select-Object -Unique) -join '/' })) -join '; ') - reports and policies see them as different." }) }
        $coverage = if ($totals.resources) { [Math]::Round(100.0 * $e.Resources / $totals.resources, 1) } else { 0 }
        $isRequired = @($RequiredTag | Where-Object { $_ -eq $name }).Count -gt 0
        if ($isRequired -and $coverage -lt $CoverageTarget) { $findings.Add(@{ S = 'Medium'; T = "Required, but on only $coverage% of resources ($($e.Resources) of $($totals.resources)) - assign a policy to require or inherit it." }) }
        $uses = $e.Resources + $e.ResourceGroups + $e.Subscriptions
        if ($uses -eq 1 -and -not $isRequired) { $findings.Add(@{ S = 'Info'; T = 'Used once - a typo, or a tag nobody else needs?' }) }
        $worst = @($findings | Sort-Object { $rank[$_.S] } | Select-Object -First 1)
        $sample = @($e.Values | Sort-Object | Select-Object -First 8)
        $item = [pscustomobject][ordered]@{
            Severity       = $(if ($worst.Count) { $worst[0].S } else { 'Info' })
            Tag            = $name
            Required       = $isRequired
            Resources      = $e.Resources
            ResourceGroups = $e.ResourceGroups
            Subscriptions  = $e.Subscriptions
            Coverage       = $coverage
            Values         = [Math]::Max($e.ValueCount, $e.Values.Count)
            SampleValues   = ($sample -join ', ') + $(if ($e.Values.Count -gt 8) { ', ...' } else { '' })
            Findings       = (@($findings | ForEach-Object { $_.T }) -join ' ')
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.TagUsage')
        $items.Add($item)
    }
    $sorted = @($items | Sort-Object -Property @{ Expression = { if ($_.Findings) { $rank[$_.Severity] } else { 9 } } }, @{ Expression = { $_.Resources + $_.ResourceGroups + $_.Subscriptions }; Descending = $true }, Tag)
    @{
        Tags    = $sorted
        Totals  = @{ Resources = $totals.resources; TaggedResources = $tagged.resources; ResourceGroups = $totals.resourceGroups; TaggedResourceGroups = $tagged.resourceGroups; Subscriptions = $totals.subscriptions; TaggedSubscriptions = $tagged.subscriptions }
        Notices = @($notices)
        Stats   = @{
            Tags        = $sorted.Count
            Findings    = @($sorted | Where-Object Findings).Count
            CaseClashes = @($sorted | Where-Object { $_.Findings -like 'Also spelled*' }).Count
            Coverage    = $(if ($totals.resources) { [Math]::Round(100.0 * $tagged.resources / $totals.resources, 1) } else { 0 })
        }
    }
}
