function Get-AACNetworkHealth {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Health of the hybrid and edge network - ExpressRoute circuits and
        gateways, VPN gateways, connections and tunnels, Azure Firewalls and
        NAT gateways - from their metrics, configuration and Resource Health:
        what the Azure Network Monitoring workbook charts, with % of capacity,
        thresholds and findings, as a heat map, a Spectre.Console view,
        objects, and CSV, PDF and interactive HTML reports.
    .DESCRIPTION
        Read-only (Reader is enough): one Resource Graph batch (the
        resources), Azure Monitor metrics over -TimeRange and each component's
        current Resource Health, several calls at once.

          ExpressRoute circuits  BGP and ARP availability per peering and
                                 link, each link's peak against the circuit's
                                 bandwidth, traffic pinned to one link, QoS
                                 drops, provisioning state, idle circuits
          ExpressRoute gateways  CPU, packets per second against the SKU,
          (VNet and Virtual WAN) routes advertised (1,000) and learned
                                 (4,000), zone-redundant SKU
          VPN and point-to-site  bandwidth against the SKU, BGP peers up or
          gateways               flapping, point-to-site users against the
                                 SKU, active-active, legacy SKUs
          connections            Connected or not, the tunnel's peak and
                                 packet drops, static routing
          Azure Firewalls        health, SNAT ports, throughput against the
                                 tier, latency, zones
          NAT gateways           data path availability, dropped packets,
                                 SNAT connections against the public IPs'
                                 ports, gateways on no subnet

        Limits are Microsoft's published figures per SKU (approximate);
        -WarnPercent (80) is where utilisation and capacity become findings
        (95% is High). The heat map scores each component 0-100 for
        availability, utilisation, drops, capacity and health.

        Every finding says when: the time of the peak, the first and last time
        it was seen in the period, or - for Resource Health - since when, in
        UTC. Each component has the time of its peak and of its Resource
        Health state; the report's header gives the period covered and when
        it was made.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Component (default) or Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Component
        ExpressRoute, Gateway (ExpressRoute gateways), Vpn (VPN and
        point-to-site gateways), Firewall, NatGateway - all by default.
        Connections come with Gateway or Vpn.
    .PARAMETER TimeRange
        How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d or 30d.
    .PARAMETER WarnPercent
        The % of capacity or of a limit at which a finding is raised (50 to
        99; 80 by default).
    .PARAMETER View
        Component or Finding: what is returned and written to -CsvPath.
    .PARAMETER ThrottleLimit
        How many metric calls run at once (1 to 32; 12 by default).
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Get-AACNetworkHealth
        The hybrid and edge network's health over the last day.
    .EXAMPLE
        Get-AACNetworkHealth -Component ExpressRoute, Gateway -TimeRange 7d -HtmlPath .\out\Network.html -PdfPath .\out\Network.pdf
        A week of ExpressRoute circuits and gateways, as reports.
    .EXAMPLE
        Get-AACNetworkHealth -View Finding -NoDisplay | Where-Object Severity -EQ 'High'
        What is down or near its limit.
    .OUTPUTS
        AAC.NetworkHealth or AAC.NetworkHealthFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.NetworkHealth', 'AAC.NetworkHealthFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('ExpressRoute', 'Gateway', 'Vpn', 'Firewall', 'NatGateway')]
        [string[]] $Component = @('ExpressRoute', 'Gateway', 'Vpn', 'Firewall', 'NatGateway'),

        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '1d',

        [ValidateRange(50, 99)]
        [int] $WarnPercent = 80,

        [ValidateSet('Component', 'Finding')]
        [string] $View = 'Component',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Network health',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $range = Get-AACTimeRange -TimeRange $TimeRange
    $end = [datetime]::UtcNow
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Component = @($Component | Select-Object -Unique); WarnPercent = $WarnPercent; ThrottleLimit = $ThrottleLimit
        Timespan = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"; Interval = $range[1]
        Period = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) to $($end.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC, every $($range[1] -replace '^PT?', '' -replace 'M$', ' min' -replace 'H$', ' h' -replace 'D$', ' day')"
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Network health' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading circuits, gateways, connections, firewalls, NAT gateways and Resource Health'
        $queries = Get-AACNetworkHealthQuery -Component $request.Component -ResourceGroupName $request.ResourceGroupName
        $read = Invoke-AACGraphBatch -Query $queries -SubscriptionId $scope.GraphScope
        $rows = $read.Rows
        # Gateways of the kinds asked for only.
        if ($rows.Contains('gateways')) {
            $rows['gateways'] = @($rows['gateways'] | Where-Object {
                    $null -ne $_ -and $(
                        $er = [string]$_['type'] -eq 'microsoft.network/expressroutegateways' -or ([string]$_['type'] -eq 'microsoft.network/virtualnetworkgateways' -and $_['properties'] -is [System.Collections.IDictionary] -and [string]$_['properties']['gatewayType'] -eq 'ExpressRoute')
                        if ($er) { 'Gateway' -in $request.Component } else { 'Vpn' -in $request.Component })
                })
        }
        $resources = @(foreach ($key in 'circuits', 'gateways', 'firewalls', 'natgateways') { if ($rows.Contains($key)) { @($rows[$key] | Where-Object { $null -ne $_ }) } })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} network component(s) and {1:N0} connection(s)' -f $resources.Count, @(if ($rows.Contains('connections')) { $rows['connections'] | Where-Object { $null -ne $_ } }).Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        $calls = @(Get-AACNetworkHealthCall -Resource $resources)
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $calls.Count)) -Description ('Reading {0:N0} metric set(s)' -f $calls.Count)
        $metrics = Read-AACMetric -Call $calls -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        $failed = @(foreach ($id in @($metrics.Keys)) { foreach ($k in @($metrics[$id].Keys)) { if ($metrics[$id][$k].Error) { "$k" } } })
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read {0:N0} metric set(s){1}' -f ($calls.Count - $failed.Count), $(if ($failed.Count) { "; $($failed.Count) unavailable" }))
        # Resource Health, each component's current status (Resource Graph doesn't have network resources').
        $targets = @(@($resources) + @(if ($rows.Contains('connections')) { $rows['connections'] | Where-Object { $null -ne $_ } }) | ForEach-Object { [string]$_['id'] })
        $statusUris = @{}
        foreach ($t in $targets) { $statusUris[$t] = "$t/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2022-10-01" }
        $statuses = if ($statusUris.Count) { Invoke-AACArmParallel -Uri @($statusUris.Values) -ThrottleLimit $request.ThrottleLimit } else { @{} }
        $rows['health'] = @(foreach ($t in @($statusUris.Keys)) {
                $answer = $statuses[$statusUris[$t]]
                $body = if ($answer -is [System.Collections.IDictionary] -and $answer.Contains('Body')) { $answer['Body'] } else { $null }
                if ($body -is [System.Collections.IDictionary] -and $body['properties'] -is [System.Collections.IDictionary]) {
                    $bp = $body['properties']
                    # Resource Health spells it occuredTime; newer versions occurredTime.
                    @{ target = $t; state = [string]$bp['availabilityState']; reason = [string]$bp['reasonType']; summary = [string]$bp['summary']; since = $(if ($bp['occurredTime']) { $bp['occurredTime'] } else { $bp['occuredTime'] }) }
                }
            })
        $result = ConvertTo-AACNetworkHealth -Read $rows -Metric $metrics -WarnPercent $request.WarnPercent -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $components = @($r.Components)
    $healthTones = @{ Available = 'good'; Degraded = 'warn'; Unavailable = 'bad'; Unknown = 'neutral' }
    $report = @{
        Subtitle = "Network health - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; Period = $request.Period; Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"; Components = $Component -join ', '; 'Warn at' = "$WarnPercent% of capacity" }
        Status   = $(if ($stats.High) { 'Failed' } elseif ($stats.Findings) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Components) { 'No network component of those kinds in scope.' } else { "$($stats.Components) component(s): $($stats.High) high finding(s) of $($stats.Findings)$(if ($stats.Down) { "; $($stats.Down) down" })" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Circuits; Label = 'ExpressRoute circuits'; Tone = 'info'; Table = 'components'; Filters = @{ Component = 'ExpressRoute circuit' } }
            @{ Value = '{0:N0}' -f $stats.Gateways; Label = 'gateways'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Connections; Label = 'connections'; Tone = 'info' }
            @{ Value = '{0:N0}' -f ($stats.Firewalls + $stats.NatGateways); Label = 'firewalls and NAT gateways'; Tone = 'info' }
            @{ Value = '{0:N0}' -f $stats.Down; Label = 'down'; Tone = $(if ($stats.Down) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Signal = 'Availability' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Components by kind'; Kind = 'donut'; CenterLabel = 'components'; Items = @($components | Group-Object Component | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'components'; Column = 'Component' }
            @{ Title = 'Peak utilisation (% of capacity)'; Items = @($components | Where-Object { $null -ne $_.PeakUtilization } | Sort-Object PeakUtilization -Descending | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = $_.PeakUtilization; Filter = $_.Name } }); Format = 'N0'; Suffix = '%'; Table = 'components'; Column = 'Name'; Tone = 'warn' }
            @{ Title = 'Findings by signal'; Items = @($r.Findings | Group-Object Signal | Sort-Object Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Signal'; Tone = 'bad' }
        )
        Tabs     = @(
            @{ Name = 'Components'; Badge = $stats.Components; Tone = 'info'; Note = 'Each circuit, gateway, connection, firewall and NAT gateway: availability, % of capacity at the peak, drops, limits and Resource Health.' }
            @{ Name = 'Findings'; Badge = $stats.Findings; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What is down, near a limit or not resilient - worst first.' }
        )
        Tables   = @(
            @{ Id = 'components'; Title = 'Components'; Section = 'Components'; Rows = $components; Noun = 'components'; GroupBy = @('Component', 'Subscription', 'Health'); ConsoleLimit = 20
                Columns = @(
                    @{ Key = 'Component'; Label = 'Component'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Availability'; Label = 'Availability %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'PeakUtilization'; Label = 'Peak % of capacity'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'CapacityUsed'; Label = '% of a limit'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Drops'; Label = 'Drops'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Health'; Label = 'Resource Health'; Type = 'badge'; Tones = $healthTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'HealthSince'; Label = 'Health since (UTC)'; Type = 'datetime' }
                    @{ Key = 'PeakAt'; Label = 'Peak at'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Sku'; Label = 'SKU'; Facet = $true }
                    @{ Key = 'Capacity'; Label = 'Capacity' }
                    @{ Key = 'State'; Label = 'State'; Facet = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Component', 'Finding', 'Severity'); ConsoleLimit = 25
                Empty = 'Nothing down or near a limit.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Component'; Label = 'Component'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Name'; Label = 'Name'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'When'; Label = 'When'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'FirstSeen'; Label = 'First seen'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'LastSeen'; Label = 'Last seen'; Type = 'datetime'; Hidden = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-Component narrows it; -TimeRange 7d looks further back; -WarnPercent moves the thresholds; -View Finding returns the findings; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $out = if ($View -eq 'Finding') { @($r.Findings) } else { $components }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $out -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $out -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
