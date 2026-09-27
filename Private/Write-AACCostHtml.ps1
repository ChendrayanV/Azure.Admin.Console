function Write-AACCostHtml {
    <#
    .SYNOPSIS
        Writes Show-AACCost's -HtmlPath report: tiles for month to date, last
        month and the period per currency; charts by month, subscription,
        service and resource group; a subscription-by-month table; and every
        detail row (subscription, month, resource group, service) in an
        interactive table that sums what is shown.
    .DESCRIPTION
        Amounts are never converted: each billing currency gets its own
        tiles and charts. Subscriptions Cost Management couldn't read are
        listed as notices.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Cost,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $CostDetail,

        [Parameter(Mandatory)]
        [datetime[]] $MonthStart,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Azure cost',

        [string] $Period,

        [System.Collections.IDictionary] $Detail
    )

    $invariant = [cultureinfo]::InvariantCulture
    $monthKeys = @($MonthStart | ForEach-Object { $_.ToString('yyyy-MM', $invariant) })
    $thisMonth = $monthKeys[-1]
    $lastMonth = if ($monthKeys.Count -gt 1) { $monthKeys[-2] } else { $null }
    $sum = {
        param($Items, [string] $Property)
        $total = 0.0
        foreach ($item in @($Items)) { $value = Get-AACPropertyValue -InputObject $item -Name $Property; if ($null -ne $value) { $total += [double]$value } }
        [Math]::Round($total, 2)
    }
    $money = { param([double] $Value, [string] $Currency) ('{0} {1:N2}' -f $Currency, $Value).Trim() }

    $read = @($Cost | Where-Object Status -eq 'OK')
    $tiles = [System.Collections.Generic.List[object]]::new()
    $charts = [System.Collections.Generic.List[object]]::new()
    $currencyGroups = @($read | Group-Object -Property Currency | Sort-Object -Property Count -Descending)
    foreach ($currencyGroup in $currencyGroups) {
        $currency = $currencyGroup.Name
        $group = @($currencyGroup.Group)
        $suffix = if ($currencyGroups.Count -gt 1) { " ($currency)" } else { '' }
        $ids = @($group | ForEach-Object { $_.SubscriptionId })
        $rows = @($CostDetail | Where-Object { $_.SubscriptionId -in $ids })
        $thisMonthRows = @($rows | Where-Object Month -eq $thisMonth)

        $tiles.Add(@{ Value = (& $money (& $sum $group 'MonthToDate') $currency); Label = "month to date$suffix"; Tone = 'good'; Table = 'detail'; Filters = @{ Month = $thisMonth; Currency = $currency } })
        if ($lastMonth) {
            $tiles.Add(@{ Value = (& $money (& $sum $group $lastMonth) $currency); Label = "last month$suffix"; Tone = 'info'; Table = 'detail'; Filters = @{ Month = $lastMonth; Currency = $currency } })
        }
        $tiles.Add(@{ Value = (& $money (& $sum $group 'Total') $currency); Label = "last $($monthKeys.Count) months$suffix"; Tone = 'violet'; Table = 'detail'; Filters = @{ Currency = $currency } })

        $byMonth = @(foreach ($key in $monthKeys) {
                @{ Label = $(if ($key -eq $thisMonth) { "$key (to date)" } else { $key }); Value = (& $sum $group $key); Filter = $key; Tone = $(if ($key -eq $thisMonth) { 'good' } else { '' }) }
            })
        $charts.Add(@{ Title = "By month$suffix"; Items = $byMonth; Format = 'N2'; Suffix = $currency; Table = 'detail'; Column = 'Month' })
        $top = {
            param([string] $Property, [int] $First = 10)
            @($thisMonthRows | Group-Object -Property $Property | ForEach-Object {
                    @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = (& $sum $_.Group 'Cost') }
                } | Where-Object { $_.Value -gt 0 } | Sort-Object -Property { $_.Value } -Descending | Select-Object -First $First)
        }
        if ($group.Count -gt 1) {
            $charts.Add(@{ Title = "Month to date by subscription$suffix"; Items = @(& $top 'SubscriptionName'); Format = 'N2'; Suffix = $currency; Table = 'detail'; Column = 'SubscriptionName'; Tone = 'violet' })
        }
        $charts.Add(@{ Title = "Month to date by service$suffix"; Items = @(& $top 'Service'); Format = 'N2'; Suffix = $currency; Table = 'detail'; Column = 'Service'; Tone = 'warn' })
        $charts.Add(@{ Title = "Month to date by resource group$suffix"; Items = @(& $top 'ResourceGroup'); Format = 'N2'; Suffix = $currency; Table = 'detail'; Column = 'ResourceGroup'; Tone = 'info' })
    }
    $tiles.Add(@{ Value = '{0:N0}' -f $read.Count; Label = 'subscriptions read'; Tone = 'neutral'; Table = 'subscriptions' })

    $notices = @(foreach ($failed in @($Cost | Where-Object Status -ne 'OK')) {
            @{ Tone = 'warn'; Text = "$($failed.SubscriptionName): $($failed.Status)" }
        })
    if ($read.Count -gt 0 -and (& $sum $read 'Total') -eq 0) {
        $notices += @{ Tone = 'info'; Text = 'Cost Management reports no cost for this period. The usage may be billed to another subscription, be covered by credits, or not be processed yet.' }
    }

    # Subscription by month: one money column per month.
    $monthColumns = @(foreach ($key in $monthKeys) {
            @{ Key = $key; Label = $(if ($key -eq $thisMonth) { "$key *" } else { $key }); Type = 'money'; Sum = $true; CurrencyKey = 'Currency' }
        })
    $subscriptionTable = @{
        Id       = 'subscriptions'
        Title    = 'By subscription and month'
        Note     = '* month to date. Totals are per currency.'
        Noun     = 'subscriptions'
        File     = 'CostBySubscription'
        Rows     = @($Cost)
        Sort     = @{ Key = 'Total'; Desc = $true }
        PageSize = 500
        Columns  = @(
            @(@{ Key = 'SubscriptionName'; Label = 'Subscription'; Nowrap = $true })
            $monthColumns
            @(
                @{ Key = 'Total'; Label = 'Total'; Type = 'money'; Sum = $true; CurrencyKey = 'Currency'; Tone = 'good' }
                @{ Key = 'Currency'; Label = 'Currency'; Facet = $true }
                @{ Key = 'TopServices'; Label = 'Top services this month'; Type = 'wide' }
                @{ Key = 'Status'; Label = 'Status'; Type = 'wide' }
                @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
            )
        )
    }
    $detailTable = @{
        Id      = 'detail'
        Title   = 'Cost detail'
        Note    = 'One row per subscription, month, resource group and service. The total of the rows shown is under the filters.'
        Noun    = 'detail rows'
        File    = 'CostDetail'
        Rows    = @($CostDetail)
        Sort    = @{ Key = 'Cost'; Desc = $true }
        GroupBy = @('Service', 'ResourceGroup', 'SubscriptionName', 'Month')
        Columns = @(
            @{ Key = 'Month'; Label = 'Month'; Facet = $true; Nowrap = $true }
            @{ Key = 'SubscriptionName'; Label = 'Subscription'; Facet = $true; Nowrap = $true }
            @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
            @{ Key = 'Service'; Label = 'Service'; Facet = $true }
            @{ Key = 'Cost'; Label = 'Cost'; Type = 'money'; Sum = $true; CurrencyKey = 'Currency' }
            @{ Key = 'Currency'; Label = 'Currency'; Facet = $true }
            @{ Key = 'SubscriptionId'; Label = 'Subscription ID'; Hidden = $true }
        )
    }

    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "Actual cost$(if ($Period) { ", $Period" })" -Fact $Detail -Tile $tiles.ToArray() -Chart $charts.ToArray() -Table @($subscriptionTable, $detailTable) -Notice $notices
}
