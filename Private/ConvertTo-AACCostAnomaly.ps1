function ConvertTo-AACCostAnomaly {
    <#
    .SYNOPSIS
        Finds the anomalies in daily cost series - spikes, drops, new spend,
        level shifts and runaway trends - with robust statistics, and
        forecasts each subscription's month end.
    .DESCRIPTION
        One series per subscription and -Dimension value (a service, a
        resource group, a region...), a value per day, missing days zero.
        For each of the last -EvaluateDays complete days, the baseline is the
        28 days before it (at least 14):
          Spike     a robust z-score - 0.6745 (x - median) / MAD - at or over
                    the threshold, and at least -MinimumImpact and 25% above
                    the median
          Drop      the same, downwards, and at least half the median: spend
                    that stopped - an outage, a deletion, a missed export
          New       no spend in the baseline, at least -MinimumImpact now
        Consecutive days of the same kind are one anomaly (Start to End).
          Trend     the least-squares line over the window fits (R squared
                    0.7 or more) and projects a rise of at least 50% over the
                    next 30 days
          Shift     otherwise, the last 7 days' total at least 30% (Low 50%,
                    High 20%) over 7 times the median of the days before, and
                    -MinimumImpact more: a new normal, not a one-day spike
        The MAD has a floor (5% of the median, and 0.5) so a flat series
        doesn't make every cent an anomaly. Thresholds by -Sensitivity: Low
        z >= 5, Medium 3.5, High 2.5.

        Severity, from the anomaly's impact against the subscription's
        average monthly spend: Critical 20% or more, High 5%, Medium
        otherwise; drops and trends are Low unless large.

        Forecast: each subscription's month to date plus the median of the
        last 7 days for each day left (so a one-off spike doesn't project), against last month's total - a finding
        when it's 20% or more higher.

        Benchmark: each subscription's last 7 days against the 7 before,
        and the median growth across subscriptions.

        Returns @{ Anomalies (AAC.CostAnomaly); Daily (one row per day:
        Date, Cost, Currency); Subscriptions (AAC.CostSubscriptionTrend);
        Stats; Notices }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Invoke-AACCostBatch's result: scope -> @{ Rows; Status }.
        [Parameter(Mandatory)]
        [hashtable] $Cost,

        # Subscription ID (lower case) -> name.
        [System.Collections.IDictionary] $SubscriptionName = @{},

        # The Cost Management dimension the series are by ('' for the subscription total).
        [string] $Dimension = 'ServiceName',

        # The label for the dimension: 'service', 'resource group'...
        [string] $DimensionLabel = 'service',

        # The last complete day (the series end).
        [Parameter(Mandatory)]
        [datetime] $End,

        [ValidateRange(14, 365)]
        [int] $Days = 60,

        [ValidateRange(1, 30)]
        [int] $EvaluateDays = 7,

        [ValidateSet('Low', 'Medium', 'High')]
        [string] $Sensitivity = 'Medium',

        [double] $MinimumImpact = 10
    )

    $value = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } else { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $threshold = @{ Low = 5.0; Medium = 3.5; High = 2.5 }[$Sensitivity]
    $shiftRatio = @{ Low = 0.5; Medium = 0.3; High = 0.2 }[$Sensitivity]
    $lastDay = $End.Date
    $start = $lastDay.AddDays( - ($Days - 1))
    $dayIndex = { param([datetime] $Day) [int]($Day.Date - $start).TotalDays }
    $toDay = {
        param($Raw)
        if ($Raw -is [datetime]) { return $Raw.Date }
        $text = [string]$Raw
        if ($text -match '^\d{8}$') { return [datetime]::ParseExact($text, 'yyyyMMdd', [cultureinfo]::InvariantCulture) }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)) { return $parsed.Date }
        $null
    }
    $median = {
        param([double[]] $Values)
        if (-not $Values.Count) { return 0.0 }
        $sorted = [double[]]($Values | Sort-Object)
        $mid = [int][Math]::Floor($sorted.Count / 2)
        if ($sorted.Count % 2) { $sorted[$mid] } else { ($sorted[$mid - 1] + $sorted[$mid]) / 2 }
    }
    $sum = { param([double[]] $Values) $t = 0.0; foreach ($v in $Values) { $t += $v }; $t }
    $round = { param([double] $N) [Math]::Round($N, 2) }

    # --- The series ---------------------------------------------------------------------------------------------
    $series = [ordered]@{}   # "subscription|name" -> @{ Subscription; Name; Currency; Values }
    $currencies = @{}
    $notices = [System.Collections.Generic.List[string]]::new()
    $unread = 0
    foreach ($scope in @($Cost.Keys | Sort-Object)) {
        $entry = $Cost[$scope]
        $subscriptionId = ($scope -replace '^/subscriptions/', '').TrimEnd('/').ToLowerInvariant()
        $subscription = if ($SubscriptionName.Contains($subscriptionId)) { [string]$SubscriptionName[$subscriptionId] } else { $subscriptionId }
        if ($entry.Status -ne 'OK') { $unread++; $notices.Add("Cost Management couldn't be read for $($subscription): $($entry.Status)"); continue }
        foreach ($row in @($entry.Rows)) {
            $day = & $toDay (& $value $row 'UsageDate')
            if (-not $day -or $day -lt $start -or $day -gt $lastDay) { continue }
            $name = if ($Dimension) { [string](& $value $row $Dimension) } else { $subscription }
            if (-not $name) { $name = '(none)' }
            $key = "$subscriptionId|$name"
            if (-not $series.Contains($key)) { $series[$key] = @{ SubscriptionId = $subscriptionId; Subscription = $subscription; Name = $name; Currency = ''; Values = [double[]]::new($Days) } }
            $series[$key].Values[(& $dayIndex $day)] += [double](& $value $row 'Cost')
            $currency = [string](& $value $row 'Currency')
            if ($currency) { $series[$key].Currency = $currency; $currencies[$currency] = $true }
        }
    }

    # --- Per subscription: monthly spend (for severity), forecast, benchmark --------------------------------------------
    $bySubscription = @{}
    foreach ($s in $series.Values) {
        if (-not $bySubscription.Contains($s.SubscriptionId)) { $bySubscription[$s.SubscriptionId] = @{ Name = $s.Subscription; Currency = $s.Currency; Values = [double[]]::new($Days) } }
        for ($i = 0; $i -lt $Days; $i++) { $bySubscription[$s.SubscriptionId].Values[$i] += $s.Values[$i] }
    }
    $monthlyOf = @{}
    foreach ($id in $bySubscription.Keys) { $monthlyOf[$id] = [Math]::Max(1.0, (& $sum $bySubscription[$id].Values) / $Days * 30) }

    $anomalies = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Series, [string] $Kind, [datetime] $From, [datetime] $To, [double] $Actual, [double] $Expected, [double] $Score)
        $impact = $Actual - $Expected
        $share = [Math]::Abs($impact) / $monthlyOf[$Series.SubscriptionId]
        $severity = if ($Kind -in 'Drop', 'Trend') { if ($share -ge 0.2) { 'Medium' } else { 'Low' } } elseif ($share -ge 0.2) { 'Critical' } elseif ($share -ge 0.05) { 'High' } else { 'Medium' }
        $span = if ($From -eq $To) { $From.ToString('d MMM') } else { "$($From.ToString('d MMM')) - $($To.ToString('d MMM'))" }
        $money = { param([double] $N) '{0:N2} {1}' -f $N, $Series.Currency }
        $text = switch ($Kind) {
            'Spike' { "$($Series.Name): spend spiked to $(& $money $Actual) on $span (expected $(& $money $Expected))" }
            'Drop' { "$($Series.Name): spend fell to $(& $money $Actual) on $span (expected $(& $money $Expected))" }
            'New' { "$($Series.Name): new spend of $(& $money $Actual) from $span" }
            'Shift' { "$($Series.Name): spend moved to a new level - $(& $money ($Actual / 7)) a day over the last 7 days (was $(& $money ($Expected / 7)))" }
            'Trend' { "$($Series.Name): spend is rising steadily - $(& $money $Actual) projected over the next 30 days (was $(& $money $Expected))" }
        }
        $remedy = switch ($Kind) {
            'Drop' { "Check the $DimensionLabel still works as it should: an outage, a deletion or a stopped workload also stops its spend. Confirm it was intended." }
            'Trend' { "Find what's growing (Cost analysis, grouped by resource) and set a budget with an alert on it before it reaches the invoice." }
            default { "Open Cost analysis for $($Series.Subscription) on $span, filtered to this $DimensionLabel and grouped by resource, and check the changes made then (Get-AACChangeHistory): a scale-out, a new SKU, a runaway job or logs ingestion. Set a budget alert on it." }
        }
        $anomalies.Add((New-AACFinding -TypeName 'AAC.CostAnomaly' -Severity $severity -Category $Kind -Finding $text -Resource $Series.Name -ResourceType $DimensionLabel -Subscription $Series.Subscription `
                    -Detail ("Robust z-score {0:N1}; {1:P0} of the subscription's average month" -f $Score, $share) -Impact ('{0}{1:N2} {2} ({3})' -f $(if ($impact -ge 0) { '+' } else { '' }), $impact, $Series.Currency, $(if ($Expected) { '{0:+0%;-0%}' -f ($impact / $Expected) } else { 'new' })) `
                    -Remediation $remedy -Effort 'Low' -Link 'https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis' -Property ([ordered]@{
                        Kind = $Kind; Dimension = $DimensionLabel; Name = $Series.Name; Start = $From; End = $To; Days = [int]($To - $From).TotalDays + 1
                        Actual = & $round $Actual; Expected = & $round $Expected; CostImpact = & $round $impact; ImpactPercent = $(if ($Expected) { & $round ($impact / $Expected * 100) } else { $null })
                        Score = [Math]::Round($Score, 2); Currency = $Series.Currency; SubscriptionId = $Series.SubscriptionId; TopResources = ''
                    })))
    }

    foreach ($s in $series.Values) {
        $v = $s.Values
        # Day by day: spikes, drops, new spend - runs of the same kind merged.
        $run = $null
        $flush = { if ($run) { & $add $s $run.Kind $run.From $run.To $run.Actual $run.Expected $run.Score } }
        for ($i = [Math]::Max(14, $Days - $EvaluateDays); $i -lt $Days; $i++) {
            $base = [double[]]@($v[([Math]::Max(0, $i - 28))..($i - 1)])
            $m = & $median $base
            $mad = & $median ([double[]]@($base | ForEach-Object { [Math]::Abs($_ - $m) }))
            $mad = [Math]::Max($mad, [Math]::Max(0.05 * $m, 0.5))
            $x = $v[$i]
            $z = 0.6745 * ($x - $m) / $mad
            # New spend: none before it - the days of the new spend itself aside.
            $continuesNew = $run -and $run.Kind -eq 'New' -and $run.To -eq $start.AddDays($i - 1) -and $x -gt 0
            $kind = if ($continuesNew -or ((& $sum $base) -lt 0.01 -and $x -ge $MinimumImpact)) { 'New' }
            elseif ($z -ge $threshold -and ($x - $m) -ge $MinimumImpact -and ($x - $m) -ge 0.25 * $m) { 'Spike' }
            elseif ($z -le - $threshold -and ($m - $x) -ge $MinimumImpact -and $x -le 0.5 * $m) { 'Drop' }
            else { $null }
            $day = $start.AddDays($i)
            if ($kind -and $run -and $run.Kind -eq $kind -and $run.To -eq $day.AddDays(-1)) {
                $run.To = $day; $run.Actual += $x; $run.Expected += $m; $run.Score = [Math]::Max([Math]::Abs($run.Score), [Math]::Abs($z)) * [Math]::Sign($z)
            }
            else {
                & $flush
                $run = if ($kind) { @{ Kind = $kind; From = $day; To = $day; Actual = $x; Expected = $m; Score = $z } } else { $null }
            }
        }
        & $flush
        if (@($anomalies | Where-Object { $_.SubscriptionId -eq $s.SubscriptionId -and $_.Name -eq $s.Name -and $_.Kind -in 'New', 'Spike' }).Count) { continue }

        # A steady rise: the least-squares line over the window, projected 30
        # days - when the line fits (R squared 0.7 or more), it's a trend, not a jump.
        $n = $Days
        $meanX = ($n - 1) / 2.0
        $meanY = (& $sum $v) / $n
        $num = 0.0; $den = 0.0; $total = 0.0
        for ($i = 0; $i -lt $n; $i++) { $num += ($i - $meanX) * ($v[$i] - $meanY); $den += ($i - $meanX) * ($i - $meanX); $total += ($v[$i] - $meanY) * ($v[$i] - $meanY) }
        $slope = if ($den) { $num / $den } else { 0 }
        $fit = if ($den -and $total) { ($num * $num) / ($den * $total) } else { 0 }
        $level = $meanY + $slope * ($n - 1 - $meanX)
        if ($meanY -gt 0 -and $level -gt 0 -and $slope -gt 0 -and $fit -ge 0.7) {
            $next30 = 30 * $level + $slope * 465   # level * 30 + slope * (1 + ... + 30)
            $last30 = & $sum ([double[]]@($v[([Math]::Max(0, $n - 30))..($n - 1)]))
            if ($last30 -gt 0 -and $next30 -ge 1.5 * $last30 -and ($next30 - $last30) -ge $MinimumImpact) {
                & $add $s 'Trend' $start $lastDay $next30 $last30 ($slope / $meanY * 100)
                continue
            }
        }
        # A new level: the last 7 days against the median of the days before.
        if ($Days -ge 28) {
            $recent = [double[]]@($v[($Days - 7)..($Days - 1)])
            $before = [double[]]@($v[([Math]::Max(0, $Days - 35))..($Days - 8)])
            $was = (& $median $before) * 7
            $now = & $sum $recent
            if ($was -gt 0 -and $now -ge $was * (1 + $shiftRatio) -and ($now - $was) -ge $MinimumImpact) {
                & $add $s 'Shift' $start.AddDays($Days - 7) $lastDay $now $was ((($now - $was) / $was) * 10)
            }
        }
    }

    # --- Forecast and benchmark ---------------------------------------------------------------------------------------
    $monthStart = [datetime]::new($lastDay.Year, $lastDay.Month, 1)
    $lastMonthStart = $monthStart.AddMonths(-1)
    $daysInMonth = [datetime]::DaysInMonth($lastDay.Year, $lastDay.Month)
    $trends = [System.Collections.Generic.List[object]]::new()
    $growths = [System.Collections.Generic.List[double]]::new()
    foreach ($id in $bySubscription.Keys) {
        $sv = $bySubscription[$id].Values
        $last7 = & $sum ([double[]]@($sv[($Days - 7)..($Days - 1)]))
        $prev7 = if ($Days -ge 14) { & $sum ([double[]]@($sv[($Days - 14)..($Days - 8)])) } else { 0 }
        $growth = if ($prev7 -gt 0) { ($last7 - $prev7) / $prev7 * 100 } else { $null }
        if ($null -ne $growth) { $growths.Add($growth) }
        $mtd = 0.0; $lastMonth = 0.0; $lastMonthDays = 0
        for ($i = 0; $i -lt $Days; $i++) {
            $day = $start.AddDays($i)
            if ($day -ge $monthStart) { $mtd += $sv[$i] }
            elseif ($day -ge $lastMonthStart) { $lastMonth += $sv[$i]; $lastMonthDays++ }
        }
        # The median day of the last 7 for each day left: a one-off spike doesn't project.
        $forecast = $mtd + (& $median ([double[]]@($sv[($Days - 7)..($Days - 1)]))) * ($daysInMonth - $lastDay.Day)
        $complete = $lastMonthDays -eq [datetime]::DaysInMonth($lastMonthStart.Year, $lastMonthStart.Month)
        $row = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.CostSubscriptionTrend'; Subscription = $bySubscription[$id].Name; Currency = $bySubscription[$id].Currency
            Last7Days = & $round $last7; Previous7Days = & $round $prev7; GrowthPercent = $(if ($null -ne $growth) { & $round $growth } else { $null })
            MonthToDate = & $round $mtd; Forecast = & $round $forecast; LastMonth = $(if ($complete) { & $round $lastMonth } else { $null })
            ForecastChangePercent = $(if ($complete -and $lastMonth -gt 0) { & $round (($forecast - $lastMonth) / $lastMonth * 100) } else { $null })
            VsPeers = ''; SubscriptionId = $id
        }
        $trends.Add($row)
        if ($complete -and $lastMonth -gt 0 -and $forecast -ge 1.2 * $lastMonth -and ($forecast - $lastMonth) -ge $MinimumImpact) {
            $s = @{ SubscriptionId = $id; Subscription = $bySubscription[$id].Name; Name = $bySubscription[$id].Name; Currency = $bySubscription[$id].Currency }
            $share = ($forecast - $lastMonth) / $monthlyOf[$id]
            $anomalies.Add((New-AACFinding -TypeName 'AAC.CostAnomaly' -Severity $(if ($share -ge 0.5) { 'High' } else { 'Medium' }) -Category 'Forecast' -Finding ("{0}: on track for {1:N2} {2} this month - {3:P0} more than last month ({4:N2})" -f $s.Name, $forecast, $s.Currency, (($forecast - $lastMonth) / $lastMonth), $lastMonth) `
                        -Resource $s.Name -ResourceType 'subscription' -Subscription $s.Subscription -Detail ('{0:N2} so far; the last 7 days'' median day for each of the {1} day(s) left' -f $mtd, ($daysInMonth - $lastDay.Day)) `
                        -Impact ('+{0:N2} {1} by month end' -f ($forecast - $lastMonth), $s.Currency) -Remediation 'Find the services behind the rise (the anomalies above, or Cost analysis grouped by service), and set a budget with a forecast alert on the subscription.' -Effort 'Low' `
                        -Link 'https://learn.microsoft.com/azure/cost-management-billing/costs/tutorial-acm-create-budgets' -Property ([ordered]@{
                            Kind = 'Forecast'; Dimension = 'subscription'; Name = $s.Name; Start = $monthStart; End = $monthStart.AddMonths(1).AddDays(-1); Days = $daysInMonth
                            Actual = & $round $forecast; Expected = & $round $lastMonth; CostImpact = & $round ($forecast - $lastMonth); ImpactPercent = & $round (($forecast - $lastMonth) / $lastMonth * 100)
                            Score = $null; Currency = $s.Currency; SubscriptionId = $id; TopResources = ''
                        })))
        }
    }
    $peerMedian = if ($growths.Count) { & $median $growths.ToArray() } else { $null }
    foreach ($t in $trends) {
        if ($null -ne $t.GrowthPercent -and $null -ne $peerMedian -and $trends.Count -gt 1) {
            $gap = $t.GrowthPercent - $peerMedian
            $t.VsPeers = if ($gap -ge 25) { 'Growing faster' } elseif ($gap -le -25) { 'Shrinking faster' } else { 'In line' }
        }
    }

    $rank = (Get-AACSeverityRank).Rank
    $sorted = @($anomalies | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, @{ Expression = { [Math]::Abs([double]$_.CostImpact) }; Descending = $true })
    $daily = @(for ($i = 0; $i -lt $Days; $i++) {
            $total = 0.0
            foreach ($b in $bySubscription.Values) { $total += $b.Values[$i] }
            [pscustomobject]@{ Date = $start.AddDays($i); Cost = & $round $total; Currency = $(if ($currencies.Count -eq 1) { @($currencies.Keys)[0] } else { 'mixed' }) }
        })
    @{
        Anomalies     = $sorted
        Daily         = $daily
        Subscriptions = @($trends | Sort-Object -Property @{ Expression = { if ($null -eq $_.GrowthPercent) { -1e9 } else { $_.GrowthPercent } }; Descending = $true })
        Notices       = $notices.ToArray()
        Stats         = @{
            Series      = $series.Count
            Anomalies   = $sorted.Count
            Critical    = @($sorted | Where-Object Severity -EQ 'Critical').Count
            High        = @($sorted | Where-Object Severity -EQ 'High').Count
            Increase    = & $round (& $sum ([double[]]@($sorted | Where-Object { $_.Kind -in 'Spike', 'New', 'Shift' } | ForEach-Object { [double]$_.CostImpact })))
            Currency    = $(if ($currencies.Count -eq 1) { @($currencies.Keys)[0] } elseif ($currencies.Count) { 'mixed' } else { '' })
            Unread      = $unread
            PeerGrowth  = $(if ($null -ne $peerMedian) { & $round $peerMedian } else { $null })
            Start       = $start
            End         = $lastDay
        }
    }
}
