function Write-AACAssessmentHtml {
    <#
    .SYNOPSIS
        Writes the Invoke-AACAssessment report as one interactive HTML page.
    .DESCRIPTION
        Tiles (subscriptions, resource groups, resources, types, locations,
        Advisor High, retirements, Defender High, policy non-compliance,
        outages, unattached resources, untagged resources, cost - each
        opening its table), charts (resources by category, location,
        subscription and type; Advisor by category; Defender by severity -
        a click filters the table), the tenant's tree (management groups >
        subscriptions > resource groups, with their resource counts), and a
        table per sheet under its category, listed in the contents - each
        collapsible, searchable, filterable, groupable and downloadable as CSV.
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
    }

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
        if (& $find 'Policy compliance') { & $tile ('{0:N0}' -f $stats.PolicyNonCompliant) 'non-compliant policy states' $(if ($stats.PolicyNonCompliant) { 'warn' } else { 'good' }) 'Policy compliance' }
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
            Id = $sheet.Id; Title = $sheet.Sheet; Section = $sheet.Category; Noun = 'rows'; File = $sheet.Id; Rows = @($sheet.Rows)
            Columns = @($columns) + @(@{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true })
            Note = ($note -join ' ')
            GroupBy = $groupBy
        }
    }

    $notices = @(foreach ($line in @($Assessment.Notices)) { @{ Tone = 'warn'; Text = $line } })
    $tree = @{ Title = 'Tenant'; OpenTo = 'm'; Root = $Assessment.Tree }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Azure environment assessment: inventory, organization, Advisor, security, policy, health and cost' -Fact $Detail -Tile $tiles -Chart $charts.ToArray() -Table @($tables) -Notice $notices -Tree $tree
}
