function Write-AACInventoryHtml {
    <#
    .SYNOPSIS
        Writes the tenant inventory (ConvertTo-AACInventory) as an
        interactive HTML report: tiles, charts, the hierarchy as a tree, and
        tables of management groups, subscriptions, resource groups and
        resources - each searchable, filterable and downloadable as CSV.
    .DESCRIPTION
        Clicking a node in the tree shows it in the tables: a management group
        its subscriptions, a subscription its resource groups, a resource
        group its resources.

        With cost (Get-AACInventory -Cost): cost tiles, each node's cost
        month to date as a pill (last month in its tooltip), charts of the
        top spenders, and cost columns - month to date, last month, currency
        - in the tables, totalled per currency (never converted); 'Deleted
        resources' lines are listed with the resources.

        With insights (Get-AACInventory -Insight): tiles, donut charts of the
        estate's mix (VM sizes, operating systems, power states, Azure and
        Arc, storage replication, database tiers) that filter a machines
        table, tag coverage, and tables of what needs attention (with cost),
        subnets (used and free IPs) and VPN and ExpressRoute connections.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Inventory,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Detail
    )

    $items = @($Inventory.Items)
    $stats = $Inventory.Stats
    $of = { param([string] $Level) @($items | Where-Object Level -EQ $Level) }
    $groups = & $of 'ManagementGroup'
    $subscriptions = & $of 'Subscription'
    $resourceGroups = @(& $of 'ResourceGroup' | ForEach-Object { $_ | Select-Object -Property *, @{ Name = 'Status'; Expression = { if ($_.Resources -eq 0) { 'Empty' } else { '' } } } })
    $resources = @(& $of 'Resource') + @(& $of 'DeletedResources' | ForEach-Object { $_ | Select-Object -Property * -ExcludeProperty Type | Select-Object -Property *, @{ Name = 'Type'; Expression = { '(deleted resources)' } } })
    $cost = [bool]$stats.HasCost
    $oneCurrency = $cost -and @($stats.Cost).Count -le 1
    $money = { param($Value, [string] $Currency) ('{0:N2} {1}' -f [double]$Value, $Currency).Trim() }

    # The tree: every node with its counts and what clicking it shows.
    $plural = { param([int] $Count, [string] $One, [string] $Many) @($Count, $(if ($Count -eq 1) { $One } else { $Many })) }
    function ConvertTo-Node($Node) {
        $n = [ordered]@{ l = @{ Tenant = 't'; ManagementGroup = 'm'; Subscription = 's'; ResourceGroup = 'g'; Resource = 'r'; DeletedResources = 'd' }[$Node.Level]; n = [string]$Node.DisplayName; d = [string]$Node.Detail }
        switch ($Node.Level) {
            { $_ -in 'Tenant', 'ManagementGroup' } {
                $n.c = @(, (& $plural $Node.Subscriptions 'subscription' 'subscriptions')) + @(, (& $plural $Node.ResourceGroups 'resource group' 'resource groups')) + @(, (& $plural $Node.Resources 'resource' 'resources'))
                $n.f = if ($Node.Level -eq 'ManagementGroup') { @{ table = 'subscriptions'; filters = @{ ManagementGroup = $Node.DisplayName } } } else { @{ table = 'subscriptions'; filters = @{} } }
            }
            'Subscription' {
                $n.c = @(, (& $plural $Node.ResourceGroups 'resource group' 'resource groups')) + @(, (& $plural $Node.Resources 'resource' 'resources'))
                $n.f = @{ table = 'groups'; filters = @{ SubscriptionId = $Node.SubscriptionId } }
            }
            'ResourceGroup' {
                $n.d = (@($Node.Detail, $Node.TopTypes) | Where-Object { $_ }) -join ' · '
                $n.c = @(, (& $plural $Node.Resources 'resource' 'resources'))
                $n.f = @{ table = 'resources'; filters = @{ SubscriptionId = $Node.SubscriptionId; ResourceGroup = $Node.ResourceGroup } }
                if ($Node.Resources -eq 0) { $n.x = 1 }
            }
            'Resource' { $n.f = @{ table = 'resources'; filters = @{ Id = $Node.Id } } }
            'DeletedResources' { $n.f = @{ table = 'resources'; filters = @{ Id = $Node.Id } }; $n.x = 1 }
        }
        # Cost: month to date as a pill, last month in its tooltip.
        if ($cost) {
            if ($Node.Level -eq 'Subscription' -and $Node.CostStatus -notin 'OK', 'No cost', '') { $n.co = 'cost not read'; $n.ct = [string]$Node.CostStatus; $n.cx = 1 }
            elseif ($Node.Currency -eq 'mixed') { $n.co = 'several currencies'; $n.ct = 'Its subscriptions are billed in different currencies, which are never converted.' }
            elseif ($Node.CostMonthToDate -gt 0 -or $Node.CostLastMonth -gt 0) { $n.co = & $money $Node.CostMonthToDate $Node.Currency; $n.ct = "Month to date; last month $(& $money $Node.CostLastMonth $Node.Currency)" }
        }
        if ($null -ne $Node.SecureScore) { $n.p = $Node.SecureScore }
        if ($Node.High) { $n.h = $Node.High }
        if ($Node.Medium) { $n.m = $Node.Medium }
        if ($Node.Low) { $n.lo = $Node.Low }
        if ($Node.Children.Count) { $n.k = @(foreach ($child in $Node.Children) { ConvertTo-Node $child }) }
        $n
    }

    $top = {
        param([object[]] $Rows, [string] $Property, [int] $First = 12)
        @($Rows | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name | Select-Object -First $First | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count; Filter = $_.Name }
            })
    }
    $notices = @()
    $tiles = @(
        @{ Value = '{0:N0}' -f $stats.ManagementGroups; Label = 'management groups'; Tone = 'violet'; Table = 'managementGroups' }
        @{ Value = '{0:N0}' -f $stats.Subscriptions; Label = 'subscriptions'; Tone = 'warn'; Table = 'subscriptions' }
        @{ Value = '{0:N0}' -f $stats.ResourceGroups; Label = 'resource groups'; Tone = 'info'; Table = 'groups' }
        @{ Value = '{0:N0}' -f $stats.Resources; Label = 'resources'; Tone = 'good'; Table = 'resources' }
        @{ Value = '{0:N0}' -f $stats.Types; Label = 'resource types'; Tone = 'neutral'; Table = 'resources' }
        @{ Value = '{0:N0}' -f $stats.Locations; Label = 'locations'; Tone = 'neutral'; Table = 'resources' }
    )
    if ($cost) {
        $costTiles = @(foreach ($total in @($stats.Cost | Select-Object -First 2)) {
                @{ Value = (& $money $total.MonthToDate $total.Currency); Label = 'cost month to date'; Tone = 'good'; Table = 'subscriptions' }
                @{ Value = (& $money $total.LastMonth $total.Currency); Label = 'cost last month'; Tone = 'info'; Table = 'subscriptions' }
            })
        $deleted = @(& $of 'DeletedResources')
        if ($deleted.Count -and $oneCurrency) {
            $deletedTotal = 0.0
            foreach ($item in $deleted) { $deletedTotal += [double]$item.CostMonthToDate }
            $costTiles += @{ Value = (& $money $deletedTotal @($stats.Cost)[0].Currency); Label = 'deleted resources this month'; Tone = 'warn'; Table = 'resources'; Filters = @{ Type = '(deleted resources)' } }
        }
        $tiles = $costTiles + $tiles
    }
    if ($stats.EmptyGroups) { $tiles += @{ Value = '{0:N0}' -f $stats.EmptyGroups; Label = 'empty resource groups'; Tone = 'bad'; Table = 'groups'; Filters = @{ Status = 'Empty' } } }
    $security = [bool]$stats.HasSecurity
    if ($security) {
        $tone = @{ Good = 'good'; Fair = 'warn'; Poor = 'bad' }
        if ($null -ne $stats.SecureScore) { $tiles = @(@{ Value = "$($stats.SecureScore)%"; Label = "secure score ($($stats.Rating.ToLowerInvariant()))"; Tone = $tone[$stats.Rating]; Table = 'controls' }) + $tiles }
        $tiles += @{ Value = '{0:N0}' -f $stats.High; Label = 'high-severity findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'recommendations'; Filters = @{ Severity = 'High' } }
        $tiles += @{ Value = '{0:N0}' -f $stats.Medium; Label = 'medium-severity findings'; Tone = $(if ($stats.Medium) { 'warn' } else { 'good' }); Table = 'recommendations'; Filters = @{ Severity = 'Medium' } }
        $tiles += @{ Value = '{0:N0}' -f $stats.Low; Label = 'low-severity findings'; Tone = 'info'; Table = 'recommendations'; Filters = @{ Severity = 'Low' } }
    }

    $charts = @(
        @{ Title = 'Resources by type'; Items = @(& $top $resources 'Type'); Table = 'resources'; Column = 'Type'; Tone = 'good' }
        @{ Title = 'Resources by location'; Items = @(& $top $resources 'Location'); Table = 'resources'; Column = 'Location' }
        @{ Title = 'Resources by subscription'; Items = @(& $top $resources 'SubscriptionName'); Table = 'resources'; Column = 'SubscriptionName'; Tone = 'warn' }
    )
    if ($cost -and @($stats.Cost).Count) {
        # The top spenders, in the main currency.
        $currency = @($stats.Cost)[0].Currency
        $topOf = {
            param([object[]] $Rows, [string] $Name)
            @($Rows | Where-Object { $_.Currency -eq $currency -and $_.CostMonthToDate -gt 0 } | Sort-Object -Property CostMonthToDate -Descending | Select-Object -First 10 | ForEach-Object {
                    @{ Label = $_.$Name; Value = $_.CostMonthToDate; Display = ('{0:N2}' -f $_.CostMonthToDate); Filter = $_.$Name }
                })
        }
        $charts = @(
            @{ Title = "Top resources this month ($currency)"; Items = @(& $topOf @($resources) 'Name'); Table = 'resources'; Column = 'Name'; Tone = 'good'; Wide = $true }
            @{ Title = "Cost this month by subscription ($currency)"; Items = @(& $topOf $subscriptions 'Name'); Table = 'subscriptions'; Column = 'Name'; Tone = 'warn' }
            @{ Title = "Top resource groups this month ($currency)"; Items = @(& $topOf $resourceGroups 'Name'); Table = 'groups'; Column = 'Name'; Tone = 'info' }
        ) + $charts
        $notices += @{ Tone = 'info'; Text = "Cost: Azure Cost Management's actual cost, month to date and last month, in each subscription's billing currency - never converted$(if (-not $oneCurrency) { '; with several currencies, totals say so rather than adding them' }). 'Deleted resources' are costs of resources no longer in Azure, and charges not tied to a resource." }
    }
    if ($security) {
        $bySeverity = @(foreach ($level in @(@('High', 'bad'), @('Medium', 'warn'), @('Low', 'info'))) {
                $count = @($Inventory.Recommendations | Where-Object Severity -EQ $level[0]).Count
                if ($count) { @{ Label = $level[0]; Value = $count; Tone = $level[1]; Filter = $level[0] } }
            })
        $gain = @($Inventory.Controls | Where-Object { $_.PotentialIncrease -gt 0 } | Sort-Object -Property @{ Expression = 'PotentialIncrease'; Descending = $true } | Select-Object -First 10 | ForEach-Object {
                @{ Label = "$($_.Control) ($($_.SubscriptionName))"; Value = $_.PotentialIncrease; Display = "+$($_.PotentialIncrease)%"; Tone = $(if ($_.PotentialIncrease -ge 5) { 'bad' } elseif ($_.PotentialIncrease -ge 2) { 'warn' } else { 'info' }); Filter = $_.Control }
            })
        $charts = @(
            @{ Title = 'Unhealthy findings by severity'; Items = $bySeverity; Table = 'recommendations'; Column = 'Severity' }
            @{ Title = 'Security controls with the most to gain'; Items = $gain; Table = 'controls'; Column = 'Control'; Wide = $true }
        ) + $charts
        $notices += @{ Tone = 'info'; Text = 'Secure score: Microsoft Defender for Cloud''s for subscriptions (added up for management groups and the tenant); for resource groups and resources, the share of their assessed recommendations that are healthy. Good 70% or more, Fair 40-69%, Poor under 40%.' }
    }

    $states = @{ Enabled = 'good'; Warned = 'warn'; PastDue = 'bad'; Disabled = 'bad'; Deleted = 'bad'; Expired = 'bad' }
    $tables = @(
        @{
            Id = 'managementGroups'; Title = 'Management groups'; Noun = 'management groups'; File = 'management-groups'; Rows = $groups
            Columns = @(
                @{ Key = 'Name'; Label = 'Management group' }
                @{ Key = 'SecureScore'; Label = 'Secure score'; Type = 'score' }
                @{ Key = 'Path'; Label = 'Path'; Type = 'wide' }
                @{ Key = 'ManagementGroups'; Label = 'Groups below'; Type = 'number' }
                @{ Key = 'Subscriptions'; Label = 'Subscriptions'; Type = 'number' }
                @{ Key = 'ResourceGroups'; Label = 'Resource groups'; Type = 'number' }
                @{ Key = 'Resources'; Label = 'Resources'; Type = 'number' }
                @{ Key = 'Id'; Label = 'ID'; Type = 'mono' }
            )
        }
        @{
            Id = 'subscriptions'; Title = 'Subscriptions'; Noun = 'subscriptions'; File = 'subscriptions'; Rows = $subscriptions; GroupBy = @('ManagementGroup', 'State')
            Columns = @(
                @{ Key = 'Name'; Label = 'Subscription'; Type = 'resource'; IdKey = 'Id' }
                @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Type = 'mono' }
                @{ Key = 'State'; Label = 'State'; Type = 'badge'; Tones = $states; Facet = $true }
                @{ Key = 'ManagementGroup'; Label = 'Management group'; Facet = $true }
                @{ Key = 'SecureScore'; Label = 'Secure score'; Type = 'score' }
                @{ Key = 'Severity'; Label = 'Worst finding'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Healthy = 'good' }; Facet = $true }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'ResourceGroups'; Label = 'Resource groups'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'TopTypes'; Label = 'Most common types'; Type = 'wide' }
                @{ Key = 'Path'; Label = 'Path'; Type = 'wide' }
                @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                @{ Key = 'Id'; Label = 'ID'; Hidden = $true }
            )
        }
        @{
            Id = 'groups'; Title = 'Resource groups'; Noun = 'resource groups'; File = 'resource-groups'; Rows = $resourceGroups; GroupBy = @('SubscriptionName', 'Location', 'ManagementGroup')
            Sort = @{ Key = 'Resources'; Desc = $true }
            Columns = @(
                @{ Key = 'Name'; Label = 'Resource group'; Type = 'resource'; IdKey = 'Id' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'ManagementGroup'; Label = 'Management group'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'Resources'; Label = 'Resources'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'SecureScore'; Label = 'Secure score'; Type = 'score' }
                @{ Key = 'Severity'; Label = 'Worst finding'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Healthy = 'good' }; Facet = $true }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'TopTypes'; Label = 'Most common types'; Type = 'wide' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Empty = 'warn' }; Facet = $true }
                @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
                @{ Key = 'Id'; Label = 'ID'; Hidden = $true }
            )
        }
        @{
            Id = 'resources'; Title = 'Resources'; Noun = 'resources'; File = 'resources'; Rows = $resources; GroupBy = @('Type', 'ResourceGroup', 'SubscriptionName', 'Location')
            Columns = @(
                @{ Key = 'Name'; Label = 'Resource'; Type = 'resource'; IdKey = 'Id' }
                @{ Key = 'Type'; Label = 'Type'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'SecureScore'; Label = 'Secure score'; Type = 'score' }
                @{ Key = 'Severity'; Label = 'Worst finding'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info'; Healthy = 'good' }; Facet = $true }
                @{ Key = 'High'; Label = 'High'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'bad' }
                @{ Key = 'Medium'; Label = 'Medium'; Type = 'number'; Sum = $true; Format = 'N0'; Tone = 'warn' }
                @{ Key = 'Low'; Label = 'Low'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'TopFindings'; Label = 'Findings'; Type = 'wide' }
                @{ Key = 'Kind'; Label = 'Kind' }
                @{ Key = 'Sku'; Label = 'SKU' }
                @{ Key = 'Zones'; Label = 'Zones' }
                @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
                @{ Key = 'ManagementGroup'; Label = 'Management group'; Hidden = $true }
                @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
                @{ Key = 'Id'; Label = 'Resource ID'; Hidden = $true }
            )
        }
    )
    if ($security) {
        $tables += @{
            Id = 'controls'; Title = 'Security controls'; Note = 'Microsoft Defender for Cloud: the potential increase is how much the subscription''s secure score rises when the control is healthy.'
            Noun = 'controls'; File = 'security-controls'; Rows = @($Inventory.Controls); Sort = @{ Key = 'PotentialIncrease'; Desc = $true }; GroupBy = @('SubscriptionName', 'Control')
            Columns = @(
                @{ Key = 'Control'; Label = 'Control' }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Score'; Label = 'Score'; Type = 'score' }
                @{ Key = 'Current'; Label = 'Points'; Type = 'number'; Format = 'N2' }
                @{ Key = 'Max'; Label = 'Out of'; Type = 'number'; Format = 'N2' }
                @{ Key = 'PotentialIncrease'; Label = 'Potential increase (%)'; Type = 'number'; Format = 'N1'; Tone = 'bad' }
                @{ Key = 'UnhealthyResources'; Label = 'Unhealthy resources'; Type = 'number'; Sum = $true; Format = 'N0' }
                @{ Key = 'HealthyResources'; Label = 'Healthy resources'; Type = 'number'; Sum = $true; Format = 'N0' }
            )
        }
        $tables += @{
            Id = 'recommendations'; Title = 'Security recommendations'; Note = 'Unhealthy Microsoft Defender for Cloud recommendations, most severe first.'
            Noun = 'findings'; File = 'security-recommendations'; Rows = @($Inventory.Recommendations); GroupBy = @('Recommendation', 'Resource', 'SubscriptionName', 'Severity')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }; Facet = $true }
                @{ Key = 'Recommendation'; Label = 'Recommendation'; Type = 'wide'; Facet = $true }
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Impact'; Label = 'User impact'; Type = 'badge'; Tones = @{ High = 'bad'; Moderate = 'warn'; Low = 'info' }; Facet = $true }
                @{ Key = 'Effort'; Label = 'Effort'; Facet = $true }
                @{ Key = 'Category'; Label = 'Category'; Facet = $true }
                @{ Key = 'Type'; Label = 'Type'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Cause'; Label = 'Cause'; Type = 'wide' }
                @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                @{ Key = 'RemediationUrl'; Label = 'Remediation'; Type = 'link'; Text = 'Open in the portal' }
            )
        }
    }
    else {
        # No Defender data: no security columns.
        foreach ($table in $tables) { $table.Columns = @($table.Columns | Where-Object { $_.Key -notin 'SecureScore', 'Severity', 'High', 'Medium', 'Low', 'TopFindings' }) }
    }
    # Cost columns, after the counts: amounts with their currency, totalled
    # for the rows shown - or '(mixed currencies)', never converted.
    $costColumns = @(
        @{ Key = 'CostMonthToDate'; Label = 'Cost month to date'; Type = 'money'; Format = 'N2'; Sum = $true; CurrencyKey = 'Currency' }
        @{ Key = 'CostLastMonth'; Label = 'Cost last month'; Type = 'money'; Format = 'N2'; Sum = $true; CurrencyKey = 'Currency' }
        @{ Key = 'Currency'; Label = 'Currency'; Facet = $true }
    )
    foreach ($table in @($tables | Where-Object { $_.Id -in 'managementGroups', 'subscriptions', 'groups', 'resources' })) {
        if (-not $cost) { continue }
        $columns = [System.Collections.Generic.List[object]]::new()
        $placed = $false
        foreach ($column in $table.Columns) {
            $columns.Add($column)
            if (-not $placed -and $column.Key -in 'Resources', 'Location') { foreach ($extra in $costColumns) { $columns.Add($extra) }; $placed = $true }
        }
        if (-not $placed) { foreach ($extra in $costColumns) { $columns.Add($extra) } }
        if ($table.Id -eq 'subscriptions') { $columns.Add(@{ Key = 'CostStatus'; Label = 'Cost data'; Type = 'badge'; Tones = @{ OK = 'good'; 'No cost' = 'neutral' }; Facet = $true }) }
        $table.Columns = $columns.ToArray()
        if ($table.Id -ne 'managementGroups') { $table.Sort = @{ Key = 'CostMonthToDate'; Desc = $true } }
    }
    # The zones column only when a resource has one.
    $resourceTable = $tables[3]
    if (-not @($resources | Where-Object Zones).Count) { $resourceTable.Columns = @($resourceTable.Columns | Where-Object { $_.Key -ne 'Zones' }) }

    # --- Insights (Get-AACInventory -Insight) --------------------------------------------------------
    $insight = $Inventory['Insight']
    if ($insight) {
        $istats = $insight.Stats
        $tiles += @(
            @{ Value = '{0:N0}' -f $istats.AzureVms; Label = 'Azure VMs'; Tone = 'info'; Table = 'machines'; Filters = @{ Kind = 'Azure VM' } }
            if ($istats.ArcServers) { @{ Value = '{0:N0}' -f $istats.ArcServers; Label = 'Azure Arc servers'; Tone = 'violet'; Table = 'machines'; Filters = @{ Kind = 'Azure Arc server' } } }
            @{ Value = '{0:N0}' -f $istats.Findings; Label = 'need attention'; Tone = $(if ($istats.Findings) { 'warn' } else { 'good' }); Table = 'attention' }
            if ($istats.StoppedBilled) { @{ Value = '{0:N0}' -f $istats.StoppedBilled; Label = 'VMs stopped but billed'; Tone = 'warn'; Table = 'attention'; Filters = @{ Finding = 'Stopped VM (still billed)' } } }
            if ($istats.UnattachedDisks) { @{ Value = "$($istats.UnattachedDisks) ($($istats.UnattachedDiskGb) GB)"; Label = 'unattached disks'; Tone = 'warn'; Table = 'attention'; Filters = @{ Finding = 'Unattached disk' } } }
            if ($null -ne $istats.WasteCost) { @{ Value = (& $money $istats.WasteCost $istats.WasteCurrency); Label = 'cost of what needs attention (this month)'; Tone = 'bad'; Table = 'attention' } }
            if ($istats.Classic) { @{ Value = '{0:N0}' -f $istats.Classic; Label = 'classic resources (retired)'; Tone = 'bad'; Table = 'attention'; Filters = @{ Finding = 'Classic resource' } } }
        )
        $donut = {
            param([string] $Title, [object[]] $Items, [string] $Table, [string] $Column, [string] $Center, [hashtable] $Tones = @{})
            @{ Title = $Title; Kind = 'donut'; CenterLabel = $Center; Table = $Table; Column = $Column; Items = @($Items | Select-Object -First 10 | ForEach-Object {
                        $item = @{ Label = [string]$_.Label; Value = $_.Value; Filter = $(if ($Table) { [string]$_.Label } else { $null }) }
                        if ($Tones.Contains([string]$_.Label)) { $item.Tone = $Tones[[string]$_.Label] }
                        $item
                    })
            }
        }
        $b = $insight.Breakdowns
        $charts += @(
            if (@($b.VmSizes).Count) { & $donut 'VM sizes' $b.VmSizes 'machines' 'Size' 'VMs' }
            if (@($b.OsVersions).Count) { & $donut 'Operating systems' $b.OsVersions 'machines' 'Os' 'machines' }
            if (@($b.PowerStates).Count) { & $donut 'VM power states' $b.PowerStates 'machines' 'PowerState' 'VMs' @{ Running = 'good'; Deallocated = 'neutral'; 'Stopped (still billed)' = 'warn' } }
            if (@($b.Hybrid).Count) { & $donut 'Azure and Azure Arc' $b.Hybrid '' '' 'machines' @{ 'Azure VMs' = 'info'; 'Arc servers (connected)' = 'violet'; 'Arc servers (not connected)' = 'bad' } }
            if (@($b.StorageReplication).Count) { & $donut 'Storage account replication' $b.StorageReplication '' '' 'accounts' }
            if (@($b.DatabaseTiers).Count) { & $donut 'Database tiers' $b.DatabaseTiers '' '' 'databases' }
            if (@($b.TagCoverage).Count) {
                @{ Title = $(if (@($istats.RequiredTags).Count) { "Required tags: resources with each ($($istats.TagCompliant) of $($istats.Resources) have them all)" } else { 'Tag coverage: resources with each of the most used tags' }); Items = @($b.TagCoverage | ForEach-Object { @{ Label = $_.Label; Value = $_.Value; Display = "$($_.Value)% ($($_.Resources))"; Tone = $(if ($_.Value -ge 90) { 'good' } elseif ($_.Value -ge 60) { 'warn' } else { 'bad' }); Filter = $null } }) }
            }
        )
        $tables += @{
            Id = 'attention'; Title = 'Needs attention'; Note = 'Waste and risk: unattached disks, unused public IPs and NICs, VMs stopped but still billed, disconnected Arc servers, classic resources, nearly full subnets, connections down and empty resource groups.'
            Noun = 'items'; File = 'needs-attention'; Rows = @($insight.Findings); GroupBy = @('Finding', 'SubscriptionName', 'Severity')
            Columns = @(
                @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = @{ High = 'bad'; Medium = 'warn'; Low = 'info' }; Facet = $true }
                @{ Key = 'Finding'; Label = 'Finding'; Facet = $true }
                @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                @{ Key = 'CostMonthToDate'; Label = 'Cost this month'; Type = 'money'; Format = 'N2'; Sum = $true; CurrencyKey = 'Currency' }
                @{ Key = 'Type'; Label = 'Type'; Facet = $true; Hidden = $true }
                @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
            )
        }
        $tables += @{
            Id = 'machines'; Title = 'Machines'; Noun = 'machines'; File = 'machines'; Rows = @($insight.Machines); GroupBy = @('Kind', 'Size', 'Os', 'PowerState', 'SubscriptionName')
            Columns = @(
                @{ Key = 'Name'; Label = 'Machine'; Type = 'resource'; IdKey = 'ResourceId' }
                @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                @{ Key = 'Size'; Label = 'Size'; Facet = $true }
                @{ Key = 'OsFamily'; Label = 'OS family'; Facet = $true }
                @{ Key = 'Os'; Label = 'Operating system'; Facet = $true }
                @{ Key = 'PowerState'; Label = 'Power state'; Type = 'badge'; Tones = @{ Running = 'good'; Deallocated = 'neutral'; 'Stopped (still billed)' = 'warn'; 'Arc: Connected' = 'good'; 'Arc: Disconnected' = 'bad'; 'Arc: Expired' = 'bad' }; Facet = $true }
                @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            )
        }
        if (@($insight.Subnets).Count) {
            $tables += @{
                Id = 'subnets'; Title = 'Subnets'; Note = 'Usable: the addresses in the prefix less the 5 Azure keeps. Used: IP configurations in the subnet (NICs, private endpoints, gateways, load balancers).'
                Noun = 'subnets'; File = 'subnets'; Rows = @($insight.Subnets); Sort = @{ Key = 'UsedPercent'; Desc = $true }; GroupBy = @('VirtualNetwork', 'SubscriptionName')
                Columns = @(
                    @{ Key = 'VirtualNetwork'; Label = 'Virtual network'; Facet = $true }
                    @{ Key = 'Subnet'; Label = 'Subnet' }
                    @{ Key = 'Prefix'; Label = 'Prefix'; Type = 'mono' }
                    @{ Key = 'UsedPercent'; Label = 'Used (%)'; Type = 'number'; Format = 'N0'; Tone = 'warn' }
                    @{ Key = 'Used'; Label = 'Used IPs'; Type = 'number'; Sum = $true; Format = 'N0' }
                    @{ Key = 'Free'; Label = 'Free IPs'; Type = 'number'; Sum = $true; Format = 'N0' }
                    @{ Key = 'Usable'; Label = 'Usable IPs'; Type = 'number'; Sum = $true; Format = 'N0' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                )
            }
        }
        if (@($insight.Connections).Count) {
            $tables += @{
                Id = 'connections'; Title = 'VPN and ExpressRoute'; Noun = 'connections'; File = 'connections'; Rows = @($insight.Connections)
                Columns = @(
                    @{ Key = 'Name'; Label = 'Connection'; Type = 'resource'; IdKey = 'ResourceId' }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Connected = 'good'; Provisioned = 'good'; NotConnected = 'bad'; Connecting = 'warn'; Unknown = 'neutral' }; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
                )
            }
        }
    }

    if ($Inventory.Contains('Notice')) { $notices += @($Inventory.Notice | Where-Object { $_ } | ForEach-Object { @{ Tone = 'info'; Text = $_ } }) }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Tenant inventory: management groups, subscriptions, resource groups and resources' -Fact $Detail `
        -Tile $tiles -Chart $charts -Table $tables -Notice $notices -Tree @{ Title = 'Hierarchy'; OpenTo = 's'; Root = (ConvertTo-Node $Inventory.Root) }
}
