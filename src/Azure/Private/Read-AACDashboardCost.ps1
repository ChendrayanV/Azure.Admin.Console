function Read-AACDashboardCost {
    <#
    .SYNOPSIS
        Show-AACDashboard -IncludeCost's cost card: month to date, the same
        days of last month, last month in all, a forecast, the last 30 days
        and the services that cost most - from one Cost Management query per
        subscription.
    .DESCRIPTION
        Reads daily actual cost by service from the first day of last month
        to today (Invoke-AACCostBatch: a few at a time, as Cost Management
        allows). Call it inside Invoke-AACProgress.

        The forecast is this month's daily average carried to the month's
        end - a straight line, not Cost Management's forecast model.
        Change compares month to date with the same days of last month, so
        a part month is never compared with a whole one.
        Returns @{ MonthToDate; LastMonthToDate; LastMonth; Forecast;
        ChangePercent; Currency; Daily (30 x @{ Day; Cost }); TopServices
        (5 x @{ Service; Cost }); Unread (subscription -> why) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $SubscriptionId,

        [hashtable] $SubscriptionName = @{},

        [datetime] $Today = [datetime]::UtcNow.Date
    )

    $invariant = [cultureinfo]::InvariantCulture
    $monthStart = [datetime]::new($Today.Year, $Today.Month, 1)
    $lastStart = $monthStart.AddMonths(-1)
    $body = @{
        type       = 'ActualCost'
        timeframe  = 'Custom'
        timePeriod = @{ from = $lastStart.ToString('yyyy-MM-ddT00:00:00Z', $invariant); to = $Today.ToString('yyyy-MM-ddT23:59:59Z', $invariant) }
        dataset    = @{
            granularity = 'Daily'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
            grouping    = @(@{ type = 'Dimension'; name = 'ServiceName' })
        }
    }
    $scopes = @($SubscriptionId | Where-Object { $_ } | ForEach-Object { "/subscriptions/$_" })
    Update-AACProgress -Id 'cost' -Total ([Math]::Max(1, $scopes.Count)) -Description "Reading costs for $($scopes.Count) subscription(s)"
    $read = Invoke-AACCostBatch -Scope $scopes -Body $body -OnProgress {
        param($Scope, $Status, $Done, $Total)
        Update-AACProgress -Id 'cost' -Increment 1 -Description "Read costs ($Done of $Total)"
    }

    $byDay = @{}
    $byService = @{}
    $currency = ''
    $unread = [ordered]@{}
    # A day comes as 20261019 (a number) or a date.
    $dayOf = {
        param($Value)
        if ($Value -is [datetime]) { return $Value.Date }
        $text = [string]$Value
        if ($text -match '^(\d{4})(\d{2})(\d{2})$') { return [datetime]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3]) }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, $invariant, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { return $parsed.Date }
        $null
    }
    foreach ($scope in $scopes) {
        $entry = if ($read.Contains($scope)) { $read[$scope] } else { @{ Rows = @(); Status = 'Not read.' } }
        if ($entry.Status -ne 'OK') {
            $id = ($scope -split '/')[-1].ToLowerInvariant()
            $unread[$(if ($SubscriptionName.Contains($id)) { $SubscriptionName[$id] } else { $id })] = [string]$entry.Status
            continue
        }
        foreach ($row in @($entry.Rows)) {
            $day = & $dayOf (Get-AACPropertyValue -InputObject $row -Name 'UsageDate')
            if (-not $day) { continue }
            $cost = [double](Get-AACPropertyValue -InputObject $row -Name 'Cost')
            if (-not $currency) { $currency = [string](Get-AACPropertyValue -InputObject $row -Name 'Currency') }
            $key = $day.ToString('yyyy-MM-dd', $invariant)
            $byDay[$key] = [double]$(if ($byDay.Contains($key)) { $byDay[$key] } else { 0 }) + $cost
            if ($day -ge $monthStart) {
                $service = [string](Get-AACPropertyValue -InputObject $row -Name 'ServiceName')
                if (-not $service) { $service = '(other)' }
                $byService[$service] = [double]$(if ($byService.Contains($service)) { $byService[$service] } else { 0 }) + $cost
            }
        }
    }
    $sumBetween = {
        param([datetime] $From, [datetime] $To)
        $total = 0.0
        foreach ($key in $byDay.Keys) { $d = [datetime]::ParseExact($key, 'yyyy-MM-dd', $invariant); if ($d -ge $From -and $d -le $To) { $total += $byDay[$key] } }
        $total
    }
    $monthToDate = & $sumBetween $monthStart $Today
    $sameDaysLastMonth = $lastStart.AddDays([Math]::Min($Today.Day, [datetime]::DaysInMonth($lastStart.Year, $lastStart.Month)) - 1)
    $lastMonthToDate = & $sumBetween $lastStart $sameDaysLastMonth
    $lastMonth = & $sumBetween $lastStart $monthStart.AddDays(-1)
    $daysInMonth = [datetime]::DaysInMonth($Today.Year, $Today.Month)
    Update-AACProgress -Id 'cost' -Complete -Description ('Month to date: {0:N0} {1}' -f $monthToDate, $currency)
    @{
        MonthToDate     = [Math]::Round($monthToDate, 2)
        LastMonthToDate = [Math]::Round($lastMonthToDate, 2)
        LastMonth       = [Math]::Round($lastMonth, 2)
        Forecast        = [Math]::Round($monthToDate / [Math]::Max(1, $Today.Day) * $daysInMonth, 2)
        ChangePercent   = $(if ($lastMonthToDate -gt 0) { [Math]::Round(100.0 * ($monthToDate - $lastMonthToDate) / $lastMonthToDate, 1) } else { $null })
        Currency        = $currency
        Daily           = @(for ($i = 29; $i -ge 0; $i--) { $d = $Today.AddDays(-$i); $k = $d.ToString('yyyy-MM-dd', $invariant); [pscustomobject]@{ Day = $d; Cost = [Math]::Round([double]$(if ($byDay.Contains($k)) { $byDay[$k] } else { 0 }), 2) } })
        TopServices     = @($byService.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 5 | ForEach-Object { [pscustomobject]@{ Service = $_.Key; Cost = [Math]::Round($_.Value, 2) } })
        Unread          = $unread
    }
}
