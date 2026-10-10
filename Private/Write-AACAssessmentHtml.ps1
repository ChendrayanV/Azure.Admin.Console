function Write-AACAssessmentHtml {
    <#
    .SYNOPSIS
        Writes the Invoke-AACAssessment report as one interactive, tabbed
        HTML workbook.
    .DESCRIPTION
        Executive summary first: tiles (subscriptions, resource groups,
        resources, types, locations, failed policies, non-compliant
        resources, critical and high recommendations, PSRule failures,
        Advisor High, retirements, Defender High, outages, unattached
        resources, untagged resources, cost - each opening its table),
        charts (policies by status - Passed, Failed, Manual review ...;
        non-compliant resources by resource group; recommendations by
        severity and by category; PSRule rules by status; resources by
        category, location, subscription and type; Advisor by category;
        Defender by severity - a click filters the table behind it) and
        the tenant's tree. Then a tab each: Policy compliance, Policy
        inventory, PSRule results, Resource recommendations, Resources,
        Inventory, Advisor, Security, Health and Cost - every table
        searchable, filterable, groupable, with each row's details a click
        away, and downloadable as CSV.
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
    $tabOf = @{ Policy = 'Policy compliance'; 'Policy inventory' = 'Policy inventory'; PSRule = 'PSRule results'; Recommendations = 'Resource recommendations'; Overview = 'Resources'; Advisor = 'Advisor'; Security = 'Security'; Health = 'Health'; Cost = 'Cost' }
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
        @{ Name = 'PSRule results'; Badge = & $stat 'PSRuleFailed'; Tone = 'warn'; Note = 'PSRule for Azure: each rule run on the resources, and the resources that failed it.' }
        @{ Name = 'Resource recommendations'; Badge = & $stat 'RecommendationsUrgent'; Tone = 'bad'; Note = 'Everything to act on in one list - under-used, misconfigured and non-compliant resources - most severe first, with what to do.' }
        @{ Name = 'Resources'; Badge = & $stat 'Resources'; Tone = 'neutral'; Note = '' }
        @{ Name = 'Inventory'; Badge = & $stat 'InventorySheets'; Tone = 'neutral'; Note = 'A sheet per resource type present, with the settings that matter for it.' }
        @{ Name = 'Advisor'; Badge = & $stat 'AdvisorHigh'; Tone = 'warn'; Note = '' }
        @{ Name = 'Security'; Badge = & $stat 'SecurityHigh'; Tone = 'bad'; Note = '' }
        @{ Name = 'Health'; Badge = & $stat 'Outages'; Tone = 'warn'; Note = '' }
        @{ Name = 'Cost'; Badge = $null; Tone = 'neutral'; Note = '' }
    )
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Azure environment assessment: policy compliance and inventory, PSRule, recommendations, inventory, Advisor, security, health and cost' -Fact $Detail -Tile $tiles -Chart $charts.ToArray() -Table @($tables) -Notice $notices -Tree $tree -Tab $tabs -OverviewTab 'Executive summary'
}
