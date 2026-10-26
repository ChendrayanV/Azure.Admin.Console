function Write-AACAssessmentHtml {
    <#
    .SYNOPSIS
        Writes the Invoke-AACTenantAssessment report as one interactive, tabbed
        HTML workbook.
    .DESCRIPTION
        Executive summary first: tiles (subscriptions, resource groups,
        resources, types, locations, failed policies, non-compliant
        resources, critical and high recommendations, the Well-Architected
        score, PSRule failures, Advisor High, retirements, Defender High,
        outages, unattached resources, untagged resources, cost, the
        estimated savings, cost-tag coverage, subscriptions without a
        budget - each opening its table), charts (policies by status -
        Passed, Failed, Manual review ...; non-compliant resources by
        resource group; recommendations by severity and by category; the
        Well-Architected pillars' scores; savings by FinOps lever; PSRule
        rules by status; resources by category, location, subscription and
        type; Advisor by category; Defender by severity - a click filters
        the table behind it) and the tenant's tree. Then a tab each: Policy
        compliance, Policy inventory, Well-Architected, PSRule results,
        Resource recommendations, FinOps, Resources, Inventory, Advisor,
        Security and Health - every table searchable, filterable,
        groupable, with each row's details a click away, and downloadable
        as CSV.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $stats = $Assessment.Stats
    $sheets = @($Assessment.Sheets)
    $find = { param([string] $Name) @($sheets | Where-Object Sheet -EQ $Name) | Select-Object -First 1 }
    $idOf = { param([string] $Name) $s = & $find $Name; if ($s) { $s.Id } else { '' } }
    $tones = @{
        High = 'bad'; Medium = 'warn'; Low = 'info'; Critical = 'bad'
        Yes = 'warn'; No = 'neutral'; Enabled = 'good'; Disabled = 'neutral'; Warned = 'warn'; Active = 'warn'; Resolved = 'good'
        Deny = 'bad'; Audit = 'warn'; AuditIfNotExists = 'warn'; DeployIfNotExists = 'info'; Modify = 'info'
        Failed = 'bad'; Passed = 'good'; 'Manual review' = 'warn'; Exempt = 'info'; 'Not evaluated' = 'neutral'; Fail = 'bad'; Pass = 'good'; Error = 'warn'
        Important = 'warn'; Awareness = 'info'; Initiative = 'violet'; Policy = 'info'; Default = 'good'; DoNotEnforce = 'warn'
        Cost = 'good'; Security = 'bad'; Reliability = 'warn'; 'Operational excellence' = 'violet'; Performance = 'info'; Governance = 'neutral'
        Initial = 'bad'; Developing = 'warn'; Established = 'info'; Optimised = 'good'; 'Not assessed' = 'neutral'; Gaps = 'warn'; Partly = 'warn'
        'Non-compliant' = 'bad'; Compliant = 'good'
        Waste = 'bad'; Rightsizing = 'warn'; Rate = 'good'; Licensing = 'info'; Usage = 'violet'; Modernise = 'neutral'
        'Over budget' = 'bad'; 'Forecast over' = 'warn'; 'No budget' = 'warn'; 'No alerts' = 'warn'; 'On track' = 'good'; 'Not read' = 'neutral'
        Permanent = 'bad'; 'Eligible (PIM)' = 'good'; 'Activated (PIM)' = 'good'; 'Time-bound' = 'info'; 'Active (PIM not read)' = 'neutral'; Expired = 'bad'; Expiring = 'warn'
        'Open to all networks' = 'bad'; 'Public, restricted' = 'warn'; 'Private only' = 'good'; 'Zone-redundant' = 'good'; 'Geo-redundant (not zonal)' = 'info'; None = 'warn'; 'No zones in this region' = 'neutral'
        Protected = 'good'; 'Not protected' = 'warn'; 'Built in' = 'good'; Replicated = 'good'; 'Missing updates' = 'bad'; 'Updates available' = 'info'; 'Up to date' = 'good'; 'Assessment stale' = 'warn'
        Connected = 'good'; Disconnected = 'bad'; Retired = 'bad'; Retiring = 'warn'; Legacy = 'neutral'; Inherited = 'good'; CanNotDelete = 'good'; ReadOnly = 'info'; Owner = 'bad'; 'User Access Administrator' = 'bad'; Root = 'bad'; 'Management group' = 'warn'; Subscription = 'info'
    }
    $statusOrder = 'Failed', 'Manual review', 'Passed', 'Exempt', 'Not evaluated', 'Disabled', 'Error'

    $tile = {
        param($Value, [string] $Label, [string] $Tone, [string] $Sheet, [hashtable] $Filters)
        $t = @{ Value = $Value; Label = $Label; Tone = $Tone }
        $id = & $idOf $Sheet
        if ($id) { $t.Table = $id; if ($Filters) { $t.Filters = $Filters } }
        $t
    }
    $tiles = @(
        & $tile ('{0:N0}' -f $stats.Subscriptions) 'subscriptions' 'info' 'Subscriptions'
        & $tile ('{0:N0}' -f $stats.ResourceGroups) "resource groups$(if ($stats.EmptyResourceGroups) { " ($($stats.EmptyResourceGroups) empty)" })" 'neutral' 'Resource groups'
        & $tile ('{0:N0}' -f $stats.Resources) 'resources' 'info' 'All resources'
        & $tile ('{0:N0}' -f $stats.ResourceTypes) "resource types in $($stats.Locations) location(s)" 'violet' 'Resource types'
        if ($null -ne $stats.Advisor) { & $tile ('{0:N0}' -f $stats.AdvisorHigh) 'Advisor High-impact recommendations' $(if ($stats.AdvisorHigh) { 'bad' } else { 'good' }) 'Advisor recommendations' @{ Impact = 'High' } }
        & $tile ('{0:N0}' -f $stats.Retirements) 'resources using retiring features' $(if ($stats.Retirements) { 'warn' } else { 'good' }) 'Retirements'
        if ($null -ne $stats.Security) { & $tile ('{0:N0}' -f $stats.SecurityHigh) 'Defender High-severity recommendations' $(if ($stats.SecurityHigh) { 'bad' } else { 'good' }) 'Security recommendations' @{ Severity = 'High' } }
        if (& $find 'Policies') { & $tile ('{0:N0}' -f $stats.PoliciesFailed) "failed of $('{0:N0}' -f $stats.Policies) policies in force" $(if ($stats.PoliciesFailed) { 'bad' } else { 'good' }) 'Policies' @{ Status = 'Failed' } }
        elseif (& $find 'Policy compliance') { & $tile ('{0:N0}' -f $stats.PolicyNonCompliant) 'non-compliant policy states' $(if ($stats.PolicyNonCompliant) { 'warn' } else { 'good' }) 'Policy compliance' }
        if (& $find 'Non-compliant resources') { & $tile ('{0:N0}' -f $stats.NonCompliantResources) 'non-compliant resources' $(if ($stats.NonCompliantResources) { 'warn' } else { 'good' }) 'Non-compliant resources' }
        if (& $find 'Resource recommendations') { & $tile ('{0:N0}' -f $stats.RecommendationsUrgent) "critical or high of $('{0:N0}' -f $stats.Recommendations) recommendations" $(if ($stats.RecommendationsUrgent) { 'bad' } else { 'good' }) 'Resource recommendations' }
        if ((& $find 'WAF pillars') -and $null -ne $stats['WafScore']) { & $tile ('{0:N0}/100' -f $stats.WafScore) "Well-Architected score ($('{0:N0}' -f $stats.WafHigh) high-severity gaps)" $(if ($stats.WafScore -ge 75) { 'good' } elseif ($stats.WafScore -ge 50) { 'warn' } else { 'bad' }) 'WAF pillars' }
        if ($stats.Contains('AnnualSavings') -and $stats.AnnualSavings) { & $tile ('{0:N0} {1}' -f $stats.AnnualSavings, $stats.SavingsCurrency) "estimated annual savings ($('{0:N0}' -f $stats.SavingsOpportunities) opportunities)" 'good' 'Savings opportunities' }
        elseif ($stats.Contains('SavingsOpportunities')) { & $tile ('{0:N0}' -f $stats.SavingsOpportunities) 'savings opportunities' $(if ($stats.SavingsOpportunities) { 'warn' } else { 'good' }) 'Savings opportunities' }
        if ($stats.Contains('CostTagCoverage') -and $null -ne $stats.CostTagCoverage) { & $tile ('{0:N0}%' -f $stats.CostTagCoverage) 'of resources have a cost-allocation tag' $(if ($stats.CostTagCoverage -ge 90) { 'good' } elseif ($stats.CostTagCoverage -ge 60) { 'warn' } else { 'bad' }) 'Cost allocation' }
        if ($stats.Contains('SubscriptionsWithoutBudget') -and $null -ne $stats.SubscriptionsWithoutBudget) { & $tile ('{0:N0}' -f $stats.SubscriptionsWithoutBudget) "subscriptions without a budget$(if ($stats.BudgetsOver) { " ($($stats.BudgetsOver) budget(s) over or forecast over)" })" $(if ($stats.SubscriptionsWithoutBudget -or $stats.BudgetsOver) { 'warn' } else { 'good' }) 'Budgets' }
        if ((& $find 'Privileged access') -and $stats.Contains('PrivilegedStanding')) { & $tile ('{0:N0}' -f $stats.PrivilegedStanding) "standing privileged assignments ($('{0:N0}' -f $stats.PrivilegedGuests) to guests)" $(if ($stats.PrivilegedStanding -or $stats.PrivilegedGuests) { 'bad' } else { 'good' }) 'Privileged access' @{ Assignment = 'Permanent' } }
        if ($stats.Contains('CredentialsExpiring')) { & $tile ('{0:N0}' -f $stats.CredentialsExpiring) 'credentials expired or expiring' $(if ($stats.CredentialsExpiring) { 'warn' } else { 'good' }) 'Expiring credentials' }
        if ($stats.Contains('ManagementPortsOpen')) { & $tile ('{0:N0}' -f $stats.ManagementPortsOpen) 'rules opening SSH or RDP to the internet' $(if ($stats.ManagementPortsOpen) { 'bad' } else { 'good' }) 'Management ports open' }
        if ($stats.Contains('SubscriptionsWithoutServiceHealth')) { & $tile ('{0:N0}' -f $stats.SubscriptionsWithoutServiceHealth) 'subscriptions with no Service Health alert' $(if ($stats.SubscriptionsWithoutServiceHealth) { 'warn' } else { 'good' }) 'Monitoring' }
        if ($stats.Contains('MachinesMissingUpdates')) { & $tile ('{0:N0}' -f $stats.MachinesMissingUpdates) 'machines missing critical or security updates' $(if ($stats.MachinesMissingUpdates) { 'warn' } else { 'good' }) 'Patch compliance' @{ Status = 'Missing updates' } }
        if ($stats.Contains('Topology')) { & $tile $stats.Topology "network topology ($('{0:N0}' -f $stats.NetworkOverlaps) overlap(s))" $(if ($stats.NetworkOverlaps) { 'warn' } else { 'info' }) 'Network topology' }
        if (& $find 'PSRule rules') { & $tile ('{0:N0}' -f $stats.PSRuleFailed) "PSRule failures ($('{0:N0}' -f $stats.PSRulePassed) passed)" $(if ($stats.PSRuleFailed) { 'warn' } else { 'good' }) 'PSRule results' }
        if (& $find 'Outages') { & $tile ('{0:N0}' -f $stats.Outages) 'Azure outages in 6 months' $(if ($stats.Outages) { 'warn' } else { 'good' }) 'Outages' }
        & $tile ('{0:N0}' -f $stats.Orphans) 'unattached or empty resources' $(if ($stats.Orphans) { 'warn' } else { 'good' }) ''
        & $tile ('{0:N0}' -f $stats.Untagged) 'resources without tags' $(if ($stats.Untagged) { 'warn' } else { 'good' }) 'All resources' @{ Tagged = 'No' }
        if ($null -ne $stats.CostMonthToDate) { & $tile ('{0:N2} {1}' -f $stats.CostMonthToDate, $stats.Currency) "cost this month (last month $('{0:N2}' -f $stats.CostLastMonth))" 'good' 'Subscriptions' }
    )

    $all = & $find 'All resources'
    $rows = @(if ($all) { $all.Rows })
    $bars = {
        param([string] $Property, [int] $Top)
        @($rows | Group-Object -Property $Property | Where-Object Name | Sort-Object Count -Descending | Select-Object -First $Top | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } })
    }
    $charts = [System.Collections.Generic.List[hashtable]]::new()
    $byValue = {
        # One item per value of a column, in the order given (then the rest), each filtering the table.
        param($Sheet, [string] $Column, [string[]] $Order)
        $counts = @($Sheet.Rows | Group-Object -Property $Column | Where-Object Name)
        $ordered = @(foreach ($name in $Order) { $counts | Where-Object Name -EQ $name }) + @($counts | Where-Object { $Order -notcontains $_.Name } | Sort-Object Count -Descending)
        @($ordered | ForEach-Object { $item = @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name }; if ($tones.Contains($_.Name)) { $item.Tone = $tones[$_.Name] }; $item })
    }
    $policies = & $find 'Policies'
    if (-not $policies) { $policies = & $find 'Compliance by initiative' }
    if ($policies -and @($policies.Rows).Count) {
        $noun = if ($policies.Sheet -eq 'Policies') { 'policies' } else { 'assignments' }
        $charts.Add(@{ Title = "$((Get-Culture).TextInfo.ToTitleCase($noun)) by compliance status"; Kind = 'donut'; CenterLabel = $noun; Items = & $byValue $policies 'Status' $statusOrder; Table = $policies.Id; Column = 'Status' })
    }
    $byGroup = & $find 'Compliance by resource group'
    if ($byGroup -and @($byGroup.Rows | Where-Object { $_.'Non-compliant' }).Count) {
        $charts.Add(@{ Title = 'Non-compliant resources by resource group'; Items = @($byGroup.Rows | Where-Object { $_.'Non-compliant' } | Sort-Object 'Non-compliant' -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = $_.'Resource group'; Value = $_.'Non-compliant'; Filter = $_.'Resource group' } }); Table = $byGroup.Id; Column = 'Resource group'; Tone = 'warn' })
    }
    $recommended = & $find 'Resource recommendations'
    if ($recommended -and @($recommended.Rows).Count) {
        $charts.Add(@{ Title = 'Recommendations by severity'; Kind = 'donut'; CenterLabel = 'recommendations'; Items = & $byValue $recommended 'Severity' @('Critical', 'High', 'Medium', 'Low'); Table = $recommended.Id; Column = 'Severity' })
        $charts.Add(@{ Title = 'Recommendations by category'; Items = & $byValue $recommended 'Category' @(); Table = $recommended.Id; Column = 'Category'; Tone = 'violet' })
    }
    $pillars = & $find 'WAF pillars'
    if ($pillars -and @($pillars.Rows | Where-Object { $null -ne $_.Score }).Count) {
        $charts.Add(@{ Title = 'Well-Architected score by pillar'; Items = @($pillars.Rows | Where-Object { $null -ne $_.Score } | ForEach-Object { @{ Label = $_.Pillar; Value = $_.Score; Display = '{0:N0}/100' -f $_.Score; Filter = $_.Pillar; Tone = $(if ($_.Score -ge 75) { 'good' } elseif ($_.Score -ge 50) { 'warn' } else { 'bad' }) } }); Table = (& $idOf 'WAF findings'); Column = 'Pillar' })
    }
    $saving = & $find 'Savings opportunities'
    if ($saving -and @($saving.Rows).Count) {
        $charts.Add(@{ Title = 'Savings opportunities by FinOps lever'; Kind = 'donut'; CenterLabel = 'opportunities'; Items = & $byValue $saving 'Lever' @('Waste', 'Rightsizing', 'Rate', 'Licensing', 'Usage', 'Modernise'); Table = $saving.Id; Column = 'Lever' })
    }
    $rules = & $find 'PSRule rules'
    if ($rules -and @($rules.Rows).Count) {
        $charts.Add(@{ Title = 'PSRule for Azure rules by status'; Kind = 'donut'; CenterLabel = 'rules'; Items = & $byValue $rules 'Status' $statusOrder; Table = $rules.Id; Column = 'Status' })
    }
    if ($rows.Count) {
        $charts.Add(@{ Title = 'Resources by category'; Kind = 'donut'; CenterLabel = 'resources'; Items = & $bars 'Category' 12; Table = $all.Id; Column = 'Category' })
        $charts.Add(@{ Title = 'Resources by location'; Items = & $bars 'Location' 12; Table = $all.Id; Column = 'Location'; Tone = 'info' })
        $charts.Add(@{ Title = 'Resources by subscription'; Items = & $bars 'Subscription' 12; Table = $all.Id; Column = 'Subscription'; Tone = 'violet' })
        $charts.Add(@{ Title = 'Most common resource types'; Items = & $bars 'Type' 15; Table = $all.Id; Column = 'Type'; Wide = $true })
    }
    $advisor = & $find 'Advisor recommendations'
    if ($advisor -and @($advisor.Rows).Count) {
        $charts.Add(@{ Title = 'Advisor recommendations by category'; Items = @($advisor.Rows | Group-Object Category | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = $advisor.Id; Column = 'Category'; Tone = 'warn' })
    }
    $security = & $find 'Security recommendations'
    if ($security -and @($security.Rows).Count) {
        $charts.Add(@{ Title = 'Defender recommendations by severity'; Items = @(foreach ($level in 'High', 'Medium', 'Low') { $n = @($security.Rows | Where-Object Severity -EQ $level).Count; if ($n) { @{ Label = $level; Value = $n; Tone = $tones[$level]; Filter = $level } } }); Table = $security.Id; Column = 'Severity' })
    }

    # Each sheet's tab: the governance ones first, the inventory's categories in one.
    $tabOf = @{ 'Identity and access' = 'Identity and access'; Architecture = 'Architecture'; Operations = 'Operations'; 'Service delivery' = 'Service delivery'; Policy = 'Policy compliance'; 'Policy inventory' = 'Policy inventory'; 'Well-Architected' = 'Well-Architected'; PSRule = 'PSRule results'; Recommendations = 'Resource recommendations'; FinOps = 'FinOps'; Cost = 'FinOps'; Overview = 'Resources'; Advisor = 'Advisor'; Security = 'Security'; Health = 'Health' }
    $tables = foreach ($sheet in $sheets) {
        if (-not @($sheet.Rows).Count -and -not $sheet.Error) { continue }
        $count = @($sheet.Rows).Count
        $columns = foreach ($label in $sheet.Columns) {
            $type = [string]$sheet.Types[$label]
            $column = @{ Key = $label; Label = $label }
            switch ($type) {
                'number' { $column.Type = 'number'; $column.Format = 'N0'; if ($label -match 'GB|%|Memory|Score|Savings|Cost|Quantity') { $column.Format = 'N2' } }
                'money' { $column.Type = 'money'; $column.Sum = $true; if ($sheet.Columns -contains 'Currency') { $column.CurrencyKey = 'Currency' } }
                'score' { $column.Type = 'score' }
                'badge' { $column.Type = 'badge'; $column.Tones = $tones; $column.Facet = $true }
                'resource' { $column.Type = 'resource'; $column.IdKey = 'ResourceId' }
                'wide' { $column.Type = 'wide' }
                'mono' { $column.Type = 'mono' }
                'link' { $column.Type = 'link'; $column.Text = 'Docs' }
            }
            if ($label -in 'Orphaned', 'Empty') { $column.Type = 'badge'; $column.Tones = @{ Yes = 'warn'; No = 'good' } }
            if (-not $column.Contains('Facet') -and $type -in 'text', 'badge', 'mono' -and $count -gt 5) {
                # A filter drop-down where there are few distinct values.
                $distinct = @($sheet.Rows | ForEach-Object { $_.$label } | Where-Object { $null -ne $_ -and "$_" -ne '' } | Select-Object -Unique -First 31).Count
                if ($label -in 'Subscription', 'Resource group', 'Location', 'Category', 'Type', 'Kind' -or ($distinct -gt 1 -and $distinct -le 30)) { $column.Facet = $true }
            }
            if ($label -in 'Tags') { $column.Type = 'wide' }
            $column
        }
        $groupBy = @($sheet.Columns | Where-Object { $_ -in 'Subscription', 'Resource group', 'Location', 'Category', 'Impact', 'Severity', 'Kind', 'SKU', 'Size', 'State', 'Status' })
        $note = @($sheet.Note, $(if ($sheet.Error) { "Couldn't be read: $($sheet.Error)" })) | Where-Object { $_ }
        @{
            Id = $sheet.Id; Title = $(if ($tabOf.Contains([string]$sheet.Category)) { $sheet.Sheet } else { "$($sheet.Category): $($sheet.Sheet)" })
            Section = $(if ($tabOf.Contains([string]$sheet.Category)) { $tabOf[[string]$sheet.Category] } else { 'Inventory' }); Noun = 'rows'; File = $sheet.Id; Rows = @($sheet.Rows)
            Columns = @($columns) + @(@{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true })
            Note = ($note -join ' ')
            GroupBy = $groupBy
        }
    }

    $notices = @(foreach ($line in @($Assessment.Notices)) { @{ Tone = 'warn'; Text = $line } })
    $tree = @{ Title = 'Tenant'; OpenTo = 'm'; Root = $Assessment.Tree }
    $stat = { param([string] $Name) if ($stats.Contains($Name)) { $stats[$Name] } else { $null } }
    $rowCount = { param([string] $Name) $s = & $find $Name; if ($s) { @($s.Rows).Count } else { $null } }
    $tabs = @(
        @{ Name = 'Policy compliance'; Badge = $(if (& $find 'Policies') { & $stat 'PoliciesFailed' } else { & $stat 'PolicyNonCompliant' }); Tone = 'bad'; Note = 'Azure Policy: compliance by initiative, by resource group and by standard, and each non-compliant resource - why, and how to fix it.' }
        @{ Name = 'Policy inventory'; Badge = & $rowCount 'Policy assignments'; Tone = 'neutral'; Note = 'The policy assignments in force on the scope, and every policy they apply: effect, resource types, controls and status.' }
        @{ Name = 'Well-Architected'; Badge = & $stat 'WafHigh'; Tone = 'warn'; Note = 'The Azure Well-Architected Framework''s five pillars, scored by pillar, design principle and check, and each check a resource fails - with what to do. Invoke-AACWafAssessment reviews one workload in depth, with the team''s answers.' }
        @{ Name = 'PSRule results'; Badge = & $stat 'PSRuleFailed'; Tone = 'warn'; Note = 'PSRule for Azure: each rule run on the resources, and the resources that failed it.' }
        @{ Name = 'Resource recommendations'; Badge = & $stat 'RecommendationsUrgent'; Tone = 'bad'; Note = 'Everything to act on in one list - under-used, misconfigured and non-compliant resources - most severe first, with what to do.' }
        @{ Name = 'FinOps'; Badge = & $stat 'SavingsOpportunities'; Tone = 'good'; Note = 'Where money can be saved (by lever), how much of the estate can be shown back to an owner, the budgets, reservations - and, with -IncludeCost, where the money goes.' }
        @{ Name = 'Identity and access'; Badge = & $stat 'PrivilegedStanding'; Tone = 'bad'; Note = 'For IT security: who holds Owner and access-granting roles at the root, management groups and subscriptions (standing, time-bound or through PIM; guests and service principals), custom roles that allow everything, classic administrators, Defender plans, credentials about to expire, management ports open to the internet and PaaS services anyone can reach.' }
        @{ Name = 'Architecture'; Badge = & $stat 'NetworkOverlaps'; Tone = 'warn'; Note = 'For architects: the landing zone (management groups, subscriptions at the root, policy coverage), regions and their pairs, the resilience of the critical resources (zones, backup, Site Recovery) and the network topology - hub and spoke or Virtual WAN, overlaps, private DNS.' }
        @{ Name = 'Operations'; Badge = & $stat 'MachinesMissingUpdates'; Tone = 'warn'; Note = 'For administrators: diagnostic settings and workspaces, Service Health alerts and silent alert rules, patching and Arc servers, locks on production, the Activity Log and failed deployments, retired SKUs, naming and owner tags.' }
        @{ Name = 'Service delivery'; Badge = & $stat 'GroupsWithoutOwner'; Tone = 'info'; Note = 'For service delivery managers: subscription offers and support plans, how much of the reservations and savings plans is used, quota headroom, the month-on-month cost trend and who owns each resource group.' }
        @{ Name = 'Resources'; Badge = & $stat 'Resources'; Tone = 'neutral'; Note = '' }
        @{ Name = 'Inventory'; Badge = & $stat 'InventorySheets'; Tone = 'neutral'; Note = 'A sheet per resource type present, with the settings that matter for it - and its policy compliance, Well-Architected gaps and Advisor recommendations.' }
        @{ Name = 'Advisor'; Badge = & $stat 'AdvisorHigh'; Tone = 'warn'; Note = '' }
        @{ Name = 'Security'; Badge = & $stat 'SecurityHigh'; Tone = 'bad'; Note = '' }
        @{ Name = 'Health'; Badge = & $stat 'Outages'; Tone = 'warn'; Note = '' }
    )
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Azure tenant assessment: policy, Well-Architected, PSRule, recommendations, FinOps, identity and access, architecture, operations, service delivery, inventory, Advisor, security and health' -Fact $Detail -Tile $tiles -Chart $charts.ToArray() -Table @($tables) -Notice $notices -Tree $tree -Tab $tabs -OverviewTab 'Executive summary'
}
