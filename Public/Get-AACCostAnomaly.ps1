function Get-AACCostAnomaly {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Finds unusual Azure spend before it reaches the invoice - spikes,
        drops, new spend, level shifts and steady rises by service, resource
        group, region or meter - with the resources behind each, a month-end
        forecast and how each subscription compares with the others.
    .DESCRIPTION
        Reads each subscription's daily cost (Cost Management, actual cost)
        for the last -Days, split by -By, and looks at each series with
        robust statistics - a median and median absolute deviation baseline
        of the 28 days before each day, so one past spike doesn't hide the
        next:
          Spike     a day well above its baseline (robust z-score at or over
                    the -Sensitivity threshold, and at least -MinimumImpact
                    and 25% more)
          Drop      a day well below - spend that stopped: an outage, a
                    deletion, something switched off
          New       spend where there was none
          Shift     the last 7 days at a new, higher level
          Trend     a steady rise projected 50% higher over 30 days
          Forecast  a subscription on track to cost 20% or more than last
                    month
        Consecutive days are one anomaly. Each has a severity - from its
        cost impact against the subscription's average month - the actual
        and expected cost, and what to do. For the largest (-RootCause, 5 by
        default) the resources behind it are read and named: the ones whose
        daily cost rose most.

        The subscriptions table compares each one's last 7 days with the 7
        before, against the median of all of them (a team or subscription
        benchmark).

        Cost data lags: today is never assessed, and -SettleDays (1)
        complete days more can be left out while Cost Management catches
        up. Cost Management allows a few queries a minute, so subscriptions
        are read three at a time.

        Needs Cost Management Reader (or Reader) on the subscriptions.
        Read-only.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER ResourceGroupName
        Only the cost of these resource groups.
    .PARAMETER By
        What each series is: ServiceName (the default), ResourceGroup,
        Location, Meter (meter category) or Subscription (its total).
    .PARAMETER Days
        How many days of history to read (21 to 365, 60 by default).
    .PARAMETER EvaluateDays
        How many of the latest days to look for spikes, drops and new spend
        in (1 to 30, 7 by default). Shifts, trends and forecasts use the
        whole window.
    .PARAMETER SettleDays
        Complete days at the end to leave out while Cost Management catches
        up (0 to 3, 1 by default).
    .PARAMETER Sensitivity
        Low (fewer, bigger anomalies), Medium (the default) or High.
    .PARAMETER MinimumImpact
        The least cost difference, in the billing currency, an anomaly must
        make (10 by default) - so cents don't count.
    .PARAMETER RootCause
        How many of the largest anomalies to find the resources behind (0 to
        20, 5 by default; each is one more Cost Management query).
    .PARAMETER CsvPath
        Write the anomalies to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report: tiles, the daily cost, anomalies by
        kind, the anomalies and the subscriptions - searchable, filterable,
        downloadable as CSV.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the anomalies.
    .PARAMETER NoDisplay
        Return the anomalies without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Get-AACCostAnomaly
        Anomalies by service in every subscription, over the last 60 days.
    .EXAMPLE
        Get-AACCostAnomaly -ManagementGroupId 'mg-landingzones' -By ResourceGroup -Sensitivity High -HtmlPath .\out\CostAnomalies.html
        Every resource group under a management group, sensitive, as an HTML report.
    .EXAMPLE
        Get-AACCostAnomaly -NoDisplay | Where-Object Severity -In 'Critical', 'High' | Select-Object Finding, CostImpact, TopResources
        The serious ones, with the resources behind them - e.g. for a daily alert.
    .OUTPUTS
        AAC.CostAnomaly
    #>
    [CmdletBinding()]
    [OutputType('AAC.CostAnomaly')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [string[]] $ManagementGroupId,

        [string[]] $ResourceGroupName,

        [ValidateSet('ServiceName', 'ResourceGroup', 'Location', 'Meter', 'Subscription')]
        [string] $By = 'ServiceName',

        [ValidateRange(21, 365)]
        [int] $Days = 60,

        [ValidateRange(1, 30)]
        [int] $EvaluateDays = 7,

        [ValidateRange(0, 3)]
        [int] $SettleDays = 1,

        [ValidateSet('Low', 'Medium', 'High')]
        [string] $Sensitivity = 'Medium',

        [ValidateRange(0, [double]::MaxValue)]
        [double] $MinimumImpact = 10,

        [ValidateRange(0, 20)]
        [int] $RootCause = 5,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Azure cost anomalies',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        By = $By; Days = $Days; EvaluateDays = $EvaluateDays; SettleDays = $SettleDays; Sensitivity = $Sensitivity; MinimumImpact = $MinimumImpact; RootCause = $RootCause
    }
    $dimension = @{ ServiceName = 'ServiceName'; ResourceGroup = 'ResourceGroupName'; Location = 'ResourceLocation'; Meter = 'MeterCategory'; Subscription = '' }[$By]
    $label = @{ ServiceName = 'service'; ResourceGroup = 'resource group'; Location = 'region'; Meter = 'meter category'; Subscription = 'subscription' }[$By]

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Cost anomalies' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        $subscriptions = @($scope.Subscriptions | Where-Object { -not $_['state'] -or $_['state'] -eq 'Enabled' })
        Update-AACProgress -Id 'scope' -Complete -Description ('Scope: {0:N0} enabled subscription(s)' -f $subscriptions.Count)

        $invariant = [cultureinfo]::InvariantCulture
        $lastDay = [datetime]::UtcNow.Date.AddDays(-1 - $request.SettleDays)
        $firstDay = $lastDay.AddDays( - ($request.Days - 1))
        $dataset = @{ granularity = 'Daily'; aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } } }
        if ($dimension) { $dataset.grouping = @(@{ type = 'Dimension'; name = $dimension }) }
        if ($request.ResourceGroupName.Count) { $dataset.filter = @{ dimensions = @{ name = 'ResourceGroupName'; operator = 'In'; values = $request.ResourceGroupName } } }
        $body = @{ type = 'ActualCost'; timeframe = 'Custom'; timePeriod = @{ from = $firstDay.ToString('yyyy-MM-ddT00:00:00Z', $invariant); to = $lastDay.ToString('yyyy-MM-ddT23:59:59Z', $invariant) }; dataset = $dataset }
        $names = @{}
        foreach ($s in $subscriptions) { $names["/subscriptions/$($s['subscriptionId'])"] = [string]$s['name'] }
        Update-AACProgress -Id 'cost' -Total ([Math]::Max(1, $subscriptions.Count)) -Description "Reading $($request.Days) days of cost for $($subscriptions.Count) subscription(s)"
        $read = Invoke-AACCostBatch -Scope @($names.Keys) -Body $body -OnProgress {
            param($CostScope, $CostStatus, $CostDone, $CostTotal)
            Update-AACProgress -Id 'cost' -Increment 1 -Description "Read the daily cost of $($names[$CostScope]) ($CostDone of $CostTotal)"
        }
        Update-AACProgress -Id 'cost' -Complete -Description ('Read the daily cost of {0:N0} subscription(s){1}' -f $read.Count, $(if (@($read.Values | Where-Object { $_.Status -ne 'OK' }).Count) { " ($(@($read.Values | Where-Object { $_.Status -ne 'OK' }).Count) couldn't be read)" }))

        Update-AACProgress -Id 'detect' -Indeterminate -Description 'Looking for spikes, drops, new spend, shifts and trends'
        $result = ConvertTo-AACCostAnomaly -Cost $read -SubscriptionName $scope.Names -Dimension $dimension -DimensionLabel $label -End $lastDay -Days $request.Days -EvaluateDays $request.EvaluateDays -Sensitivity $request.Sensitivity -MinimumImpact $request.MinimumImpact
        Update-AACProgress -Id 'detect' -Complete -Description ('{0:N0} series: {1:N0} anomaly(ies), {2:N0} critical or high' -f $result.Stats.Series, $result.Stats.Anomalies, ($result.Stats.Critical + $result.Stats.High))

        # The resources behind the largest rises.
        $rising = @($result.Anomalies | Where-Object { $_.Kind -in 'Spike', 'New', 'Shift' } | Sort-Object -Property @{ Expression = { [double]$_.CostImpact }; Descending = $true } | Select-Object -First $request.RootCause)
        if ($rising.Count) {
            Update-AACProgress -Id 'rootcause' -Total $rising.Count -Description "Finding the resources behind the $($rising.Count) largest anomaly(ies)"
            foreach ($anomaly in $rising) {
                $from = ([datetime]$anomaly.Start).AddDays(-7)
                $rootDataset = @{ granularity = 'Daily'; aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }; grouping = @(@{ type = 'Dimension'; name = 'ResourceId' }) }
                $filters = @(if ($dimension -and $anomaly.Name -ne '(none)') { @{ dimensions = @{ name = $dimension; operator = 'In'; values = @($anomaly.Name) } } })
                if ($request.ResourceGroupName.Count) { $filters += @{ dimensions = @{ name = 'ResourceGroupName'; operator = 'In'; values = $request.ResourceGroupName } } }
                if ($filters.Count -eq 1) { $rootDataset.filter = $filters[0] } elseif ($filters.Count -gt 1) { $rootDataset.filter = @{ and = $filters } }
                $rootBody = @{ type = 'ActualCost'; timeframe = 'Custom'; timePeriod = @{ from = $from.ToString('yyyy-MM-ddT00:00:00Z', $invariant); to = ([datetime]$anomaly.End).ToString('yyyy-MM-ddT23:59:59Z', $invariant) }; dataset = $rootDataset }
                $rootRead = Invoke-AACCostBatch -Scope @("/subscriptions/$($anomaly.SubscriptionId)") -Body $rootBody
                $entry = @($rootRead.Values)[0]
                if ($entry -and $entry.Status -eq 'OK') {
                    $top = @(Get-AACCostContributor -Rows @($entry.Rows) -Start $anomaly.Start -End $anomaly.End -Top 3)
                    $anomaly.TopResources = (@($top | ForEach-Object { '{0} (+{1:N2} a day)' -f $_.Resource, $_.Change })) -join ', '
                }
                Update-AACProgress -Id 'rootcause' -Increment 1
            }
            Update-AACProgress -Id 'rootcause' -Complete -Description "Named the resources behind $($rising.Count) anomaly(ies)"
        }
        @{ Result = $result; Scope = $scope; Subscriptions = $subscriptions }
    }

    $result = $state.Result
    $stats = $result.Stats
    $currency = $stats.Currency
    $severity = Get-AACSeverityRank
    $kindTones = @{ Spike = 'bad'; New = 'warn'; Shift = 'warn'; Trend = 'violet'; Forecast = 'warn'; Drop = 'info' }
    $status = if ($stats.Critical -or $stats.High) { 'Failed' } elseif ($stats.Anomalies -or $stats.Unread) { 'Warning' } else { 'Success' }
    $report = @{
        Subtitle = "Cost anomalies by $label, $($stats.Start.ToString('d MMM')) to $($stats.End.ToString('d MMM yyyy'))"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; By = $label; Window = "$($request.Days) days to $($stats.End.ToString('d MMM yyyy'))"; Sensitivity = $request.Sensitivity; 'Minimum impact' = "$($request.MinimumImpact) $currency".Trim() }
        Status   = $status
        Headline = $(if ($stats.Anomalies) { "$($stats.Anomalies) anomaly(ies) - $($stats.Critical) critical, $($stats.High) high; rises add up to $('{0:N2}' -f $stats.Increase) $currency" } else { "No anomalies: every $label's spend is in line with its baseline." })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Anomalies; Label = 'anomalies'; Tone = $(if ($stats.Anomalies) { 'warn' } else { 'good' }); Table = 'anomalies' }
            @{ Value = '{0:N0}' -f ($stats.Critical + $stats.High); Label = 'critical or high'; Tone = $(if ($stats.Critical + $stats.High) { 'bad' } else { 'good' }); Table = 'anomalies' }
            @{ Value = '{0:N0}' -f $stats.Increase; Label = "rise in $currency".Trim(); Tone = $(if ($stats.Increase) { 'bad' } else { 'good' }) }
            @{ Value = '{0:N0}' -f $stats.Series; Label = "$label series checked"; Tone = 'info' }
            @{ Value = '{0:N0}' -f @($result.Subscriptions).Count; Label = 'subscriptions'; Tone = 'neutral'; Table = 'subscriptions' }
            @{ Value = $(if ($null -ne $stats.PeerGrowth) { '{0:+0;-0;0}%' -f $stats.PeerGrowth } else { '-' }); Label = 'median growth, 7 days'; Tone = 'violet' }
        )
        Notices  = @($result.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        Charts   = @(
            @{ Title = "Daily cost, last 30 days ($currency)".Replace(' ()', ''); Items = @($result.Daily | Select-Object -Last 30 | ForEach-Object { @{ Label = $_.Date.ToString('d MMM'); Value = $_.Cost } }); Wide = $true; Tone = 'info' }
            @{ Title = 'Anomalies by kind'; Kind = 'donut'; CenterLabel = 'anomalies'; Items = @($result.Anomalies | Group-Object Kind | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Tone = $kindTones[$_.Name]; Filter = $_.Name } }); Table = 'anomalies'; Column = 'Kind' }
            @{ Title = 'Daily cost, last 14 days'; Items = @($result.Daily | Select-Object -Last 14 | ForEach-Object { @{ Label = $_.Date.ToString('ddd d MMM'); Value = $_.Cost } }); Console = $true; NoHtml = $true }
        )
        Tables   = @(
            @{ Id = 'anomalies'; Title = 'Anomalies'; Section = 'Anomalies'; Rows = $result.Anomalies; Noun = 'anomalies'; GroupBy = @('Severity', 'Kind', 'Subscription')
                Empty = "No anomalies in the last $($request.EvaluateDays) day(s) at $($request.Sensitivity.ToLowerInvariant()) sensitivity."
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $severity.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = $label.Substring(0, 1).ToUpperInvariant() + $label.Substring(1); Console = $true; Pdf = $true; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Start'; Label = 'From'; Type = 'date'; Pdf = $true }
                    @{ Key = 'CostImpact'; Label = 'Impact'; Type = 'money'; CurrencyKey = 'Currency'; Console = $true; Pdf = $true; Format = 'N2' }
                    @{ Key = 'ImpactPercent'; Label = 'Impact (%)'; Type = 'number'; Format = 'N0' }
                    @{ Key = 'Actual'; Label = 'Actual'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'Expected'; Label = 'Expected'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'Finding'; Label = 'Finding'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'TopResources'; Label = 'Resources behind it'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Evidence'; Type = 'wide' }
                    @{ Key = 'Remediation'; Label = 'What to do'; Type = 'wide' }
                    @{ Key = 'Currency'; Label = 'Currency'; Hidden = $true }
                ) }
            @{ Id = 'subscriptions'; Title = 'Subscriptions: last 7 days against the 7 before'; Section = 'Subscriptions'; Rows = $result.Subscriptions; Noun = 'subscriptions'
                Columns = @(
                    @{ Key = 'Subscription'; Label = 'Subscription'; Console = $true }
                    @{ Key = 'Last7Days'; Label = 'Last 7 days'; Type = 'money'; CurrencyKey = 'Currency'; Console = $true }
                    @{ Key = 'Previous7Days'; Label = '7 days before'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'GrowthPercent'; Label = 'Growth (%)'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'VsPeers'; Label = 'Against the others'; Type = 'badge'; Tones = @{ 'Growing faster' = 'bad'; 'In line' = 'good'; 'Shrinking faster' = 'info' }; Console = $true }
                    @{ Key = 'MonthToDate'; Label = 'Month to date'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'Forecast'; Label = 'Month-end forecast'; Type = 'money'; CurrencyKey = 'Currency'; Console = $true }
                    @{ Key = 'LastMonth'; Label = 'Last month'; Type = 'money'; CurrencyKey = 'Currency' }
                    @{ Key = 'ForecastChangePercent'; Label = 'Forecast vs last month (%)'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'Currency'; Label = 'Currency'; Hidden = $true }
                ) }
            @{ Id = 'daily'; Title = 'Daily cost'; Section = 'Daily cost'; Rows = $result.Daily; NoConsole = $true; Columns = @(@{ Key = 'Date'; Label = 'Date'; Type = 'date' }, @{ Key = 'Cost'; Label = 'Cost'; Type = 'money'; CurrencyKey = 'Currency' }, @{ Key = 'Currency'; Label = 'Currency'; Hidden = $true }) }
        )
        Hint     = '-By ServiceName|ResourceGroup|Location|Meter|Subscription; -Sensitivity Low|High; -NoDisplay returns the anomalies; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject @($result.Anomalies) -Noun 'anomaly' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object @($result.Anomalies) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
