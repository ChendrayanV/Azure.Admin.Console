function Write-AACResourceHtml {
    <#
    .SYNOPSIS
        Writes Show-AACResource's -HtmlPath report: an interactive inventory
        of every resource, with tiles for the totals and charts by type,
        location, subscription and resource group that filter it.
    .DESCRIPTION
        -Resource is one row per resource (Name, Type, ResourceGroup,
        Location, SubscriptionName, SubscriptionId, Kind, Sku, Tags,
        ResourceId), from Show-AACResource's inventory query.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Resource,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure resources',

        [System.Collections.IDictionary] $Detail
    )

    $distinct = { param([string] $Property) @($Resource | ForEach-Object { [string]$_.$Property } | Where-Object { $_ } | Select-Object -Unique).Count }
    $top = {
        param([string] $Property, [int] $First = 12)
        $groups = @($Resource | Group-Object -Property $Property | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, Name)
        $items = @($groups | Select-Object -First $First | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = $_.Count } })
        $rest = @($groups | Select-Object -Skip $First)
        if ($rest.Count) {
            $sum = 0
            foreach ($group in $rest) { $sum += $group.Count }
            $items += @{ Label = "$($rest.Count) more"; Value = $sum; Tone = 'neutral'; Filter = $null }
        }
        $items
    }

    $tiles = @(
        @{ Value = '{0:N0}' -f $Resource.Count; Label = 'resources'; Tone = 'info'; Table = 'resources' }
        @{ Value = '{0:N0}' -f (& $distinct 'Type'); Label = 'resource types'; Tone = 'violet' }
        @{ Value = '{0:N0}' -f (& $distinct 'SubscriptionId'); Label = 'subscriptions'; Tone = 'good' }
        @{ Value = '{0:N0}' -f @($Resource | ForEach-Object { "$($_.SubscriptionId)/$($_.ResourceGroup)".ToLowerInvariant() } | Select-Object -Unique).Count; Label = 'resource groups'; Tone = 'warn' }
        @{ Value = '{0:N0}' -f (& $distinct 'Location'); Label = 'locations'; Tone = 'neutral' }
    )
    $charts = @(
        @{ Title = 'By type'; Items = @(& $top 'Type'); Table = 'resources'; Column = 'Type' }
        @{ Title = 'By location'; Items = @(& $top 'Location'); Table = 'resources'; Column = 'Location'; Tone = 'violet' }
        @{ Title = 'By subscription'; Items = @(& $top 'SubscriptionName'); Table = 'resources'; Column = 'SubscriptionName'; Tone = 'good' }
        @{ Title = 'By resource group'; Items = @(& $top 'ResourceGroup'); Table = 'resources'; Column = 'ResourceGroup'; Tone = 'warn' }
    )
    $table = @{
        Id      = 'resources'
        Title   = 'Resources'
        Noun    = 'resources'
        File    = 'AzureResources'
        Rows    = $Resource
        Sort    = @{ Key = 'Name' }
        GroupBy = @('Type', 'ResourceGroup', 'Location', 'SubscriptionName')
        Columns = @(
            @{ Key = 'Name'; Label = 'Name'; Type = 'resource' }
            @{ Key = 'Type'; Label = 'Type'; Facet = $true; Nowrap = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
            @{ Key = 'Location'; Label = 'Location'; Facet = $true }
            @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true }
            @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
            @{ Key = 'Sku'; Label = 'SKU'; Facet = $true }
            @{ Key = 'Tags'; Label = 'Tags'; Type = 'wide' }
            @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
            @{ Key = 'ResourceId'; Label = 'Resource ID'; Hidden = $true }
        )
    }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f $Resource.Count) resources" -Fact $Detail -Tile $tiles -Chart $charts -Table @($table)
}
