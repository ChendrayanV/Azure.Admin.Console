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
    $resources = & $of 'Resource'

    # The tree: every node with its counts and what clicking it shows.
    $plural = { param([int] $Count, [string] $One, [string] $Many) @($Count, $(if ($Count -eq 1) { $One } else { $Many })) }
    function ConvertTo-Node($Node) {
        $n = [ordered]@{ l = @{ Tenant = 't'; ManagementGroup = 'm'; Subscription = 's'; ResourceGroup = 'g'; Resource = 'r' }[$Node.Level]; n = [string]$Node.DisplayName; d = [string]$Node.Detail }
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
            )
        }
    }
    else {
        # No Defender data: no security columns.
        foreach ($table in $tables) { $table.Columns = @($table.Columns | Where-Object { $_.Key -notin 'SecureScore', 'Severity', 'High', 'Medium', 'Low', 'TopFindings' }) }
    }
    # The zones column only when a resource has one.
    $resourceTable = $tables[3]
    if (-not @($resources | Where-Object Zones).Count) { $resourceTable.Columns = @($resourceTable.Columns | Where-Object { $_.Key -ne 'Zones' }) }

    if ($Inventory.Contains('Notice')) { $notices += @($Inventory.Notice | Where-Object { $_ } | ForEach-Object { @{ Tone = 'info'; Text = $_ } }) }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle 'Tenant inventory: management groups, subscriptions, resource groups and resources' -Fact $Detail `
        -Tile $tiles -Chart $charts -Table $tables -Notice $notices -Tree @{ Title = 'Hierarchy'; OpenTo = 's'; Root = (ConvertTo-Node $Inventory.Root) }
}
