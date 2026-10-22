function Invoke-AACCosmosDBAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Azure Cosmos DB accounts across subscriptions -
        availability, rate limiting (429), errors, throughput and its use,
        storage, every database and container, security, resilience and
        cost - as a heat map, findings, a Spectre.Console view, objects, and
        CSV, PDF and interactive HTML reports.
    .DESCRIPTION
        Read-only (Reader is enough), for every API - NoSQL, MongoDB,
        Cassandra, Gremlin and Table:
          Resource Graph    the accounts: regions, failover, consistency,
                            backup, capabilities (API, serverless), network
                            access, local authentication, TLS, encryption -
                            and the Defender for Azure Cosmos DB plan and its
                            alerts
          Resource Manager  each account's databases and containers, their
                            throughput (manual or autoscale, at the database
                            or the container), and where its logs go
          metrics           over -TimeRange: TotalRequests by status code,
                            TotalRequestUnits, NormalizedRUConsumption (the
                            busiest partition's share of its throughput),
                            ServiceAvailability, ServerSideLatency; and the
                            latest DataUsage, IndexUsage and DocumentCount

        Findings (High, Medium, Low):
          availability  service availability below 99.99%
          throttling    requests rate limited (429), running close to the
                        throughput
          errors        server errors (5xx), slow server-side latency
          security      TLS below 1.2, open to every network, account keys
                        allowed, keys able to change databases and
                        containers, no logs to Log Analytics, Defender off
                        or alerting
          resilience    a single region, no automatic failover, no
                        availability zones, periodic backup only (or stored
                        in one datacentre), Strong consistency across regions
          cost          throughput higher than needed, no requests in the
                        period, many small containers with their own
                        throughput

        The heat map scores each account 0-100 for availability, throttling,
        errors, security, resilience and cost - the 40 worst at the prompt
        and in the reports; clicking a cell in the HTML lists its findings.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Account (default), Container or Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only accounts with these names; wildcards work.
    .PARAMETER TimeRange
        How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
        or 30d. Storage is always the latest value.
    .PARAMETER View
        Account, Container or Finding: what is returned and written to -CsvPath.
    .PARAMETER ThrottleLimit
        How many requests run at once (1 to 32; 12 by default).
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
        Invoke-AACCosmosDBAssessment
        Every account's availability, throttling, throughput, posture and findings over the last day.
    .EXAMPLE
        Invoke-AACCosmosDBAssessment -NoDisplay | Where-Object Throttled | Select-Object -Property Account, Throttled, ThrottleRate, NormalizedRuMax, ProvisionedRU, AutoscaleMaxRU
        The accounts rate limiting requests, and the throughput they have.
    .EXAMPLE
        Invoke-AACCosmosDBAssessment -View Container -NoDisplay | Where-Object ThroughputMode -EQ 'Manual' | Sort-Object -Property RU -Descending
        The containers with manual throughput, the most first - candidates for autoscale.
    .EXAMPLE
        Invoke-AACCosmosDBAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\out\CosmosDB.html -PdfPath .\out\CosmosDB.pdf
        A week of a workload's accounts, as reports.
    .OUTPUTS
        AAC.CosmosDBAssessment, AAC.CosmosDBContainer or AAC.CosmosDBFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.CosmosDBAssessment', 'AAC.CosmosDBContainer', 'AAC.CosmosDBFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [string[]] $Name,

        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '1d',

        [ValidateSet('Account', 'Container', 'Finding')]
        [string] $View = 'Account',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Cosmos DB assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # TimeRange -> hours and the metric grain (an interval Azure Monitor accepts).
    $range = Get-AACTimeRange -TimeRange $TimeRange
    $end = [datetime]::UtcNow
    $span = { param([int] $Hours) "$($end.AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))" }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Timespan = & $span $range[0]; Interval = $range[1]
        # ServiceAvailability is hourly at the finest.
        AvailabilityInterval = $(if ($range[1] -in 'PT5M', 'PT15M', 'PT30M') { 'PT1H' } else { $range[1] })
        # Storage is reported every few minutes to hourly: at least two days back, for the latest value.
        StorageTimespan = & $span ([Math]::Max(48, $range[0])); ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Cosmos DB assessment' -Color 'mediumorchid' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the Cosmos DB accounts and Defender (Resource Graph)'
        $read = Invoke-AACGraphBatch -Query (Get-AACCosmosDBQuery -ResourceGroupName $request.ResourceGroupName) -SubscriptionId $scope.GraphScope -AllowFailure @('pricing', 'alerts', 'workspaces')
        $accounts = @($read.Rows['accounts'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $request.Name.Count -or @($request.Name | Where-Object { $n -like $_ }).Count) })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} account(s)' -f $accounts.Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        # Each account's API and capacity mode decide where its databases are, and whether they have throughput.
        $described = foreach ($a in $accounts) {
            $props = $a['properties']
            $caps = @(@(if ($props -is [System.Collections.IDictionary]) { $props['capabilities'] }) | Where-Object { $_ } | ForEach-Object { [string]$_['name'] })
            $api = if ([string]$a['kind'] -eq 'MongoDB' -or $caps -contains 'EnableMongo') { 'MongoDB' } elseif ($caps -contains 'EnableCassandra') { 'Cassandra' } elseif ($caps -contains 'EnableGremlin') { 'Gremlin' } elseif ($caps -contains 'EnableTable') { 'Table' } else { 'NoSQL' }
            @{ Id = [string]$a['id']; Api = $api; Serverless = $caps -contains 'EnableServerless' }
        }
        $described = @($described)
        Update-AACProgress -Id 'resources' -Indeterminate -Description "Reading the databases, containers and throughput of $($described.Count) account(s)"
        $resources = Read-AACCosmosDBResource -Account $described -ThrottleLimit $request.ThrottleLimit
        Update-AACProgress -Id 'resources' -Complete -Description ('Read the databases and containers of {0:N0} account(s)' -f $described.Count)

        $main = foreach ($a in $described) {
            @{ Id = $a.Id; Key = 'Requests'; Metric = @('TotalRequests'); Aggregation = @('Count'); Filter = "StatusCode eq '*'" }
            @{ Id = $a.Id; Key = 'Usage'; Metric = @('TotalRequestUnits', 'NormalizedRUConsumption'); Aggregation = @('Total', 'Maximum'); Filter = '' }
            @{ Id = $a.Id; Key = 'Latency'; Metric = @('ServerSideLatency'); Aggregation = @('Average'); Filter = '' }
        }
        $availabilityCalls = @(foreach ($a in $described) { @{ Id = $a.Id; Key = 'Availability'; Metric = @('ServiceAvailability'); Aggregation = @('Average'); Filter = '' } })
        $storageCalls = @(foreach ($a in $described) { @{ Id = $a.Id; Key = 'Storage'; Metric = @('DataUsage', 'IndexUsage', 'DocumentCount'); Aggregation = @('Total'); Filter = '' } })
        $main = @($main)
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $main.Count + $availabilityCalls.Count + $storageCalls.Count)) -Description 'Reading the metrics (Azure Monitor)'
        $tick = { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        $metrics = Read-AACMetric -Call $main -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        $more = @(
            (Read-AACMetric -Call $availabilityCalls -Timespan $request.Timespan -Interval $request.AvailabilityInterval -ThrottleLimit $request.ThrottleLimit -OnProgress $tick)
            (Read-AACMetric -Call $storageCalls -Timespan $request.StorageTimespan -Interval 'PT1H' -ThrottleLimit $request.ThrottleLimit -OnProgress $tick)
        )
        foreach ($set in $more) { foreach ($id in @($set.Keys)) { if (-not $metrics.Contains($id)) { $metrics[$id] = @{} }; foreach ($k in @($set[$id].Keys)) { $metrics[$id][$k] = $set[$id][$k] } } }
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read the metrics of {0:N0} account(s)' -f $described.Count)
        $failedMetrics = @($described | Where-Object { $m = $metrics[$_.Id]; $m -and $m['Requests'] -and $m['Requests'].Error }).Count
        if ($failedMetrics) { $notices.Add("Metrics couldn't be read for $failedMetrics account(s) - their health is left blank (see MetricsError).") }
        $unread = @($described | Where-Object { $resources[$_.Id].Error }).Count
        if ($unread) { $notices.Add("The databases of $unread account(s) couldn't be read - their containers and throughput are left out (see ResourcesError).") }

        $workspaceName = @{}
        foreach ($w in @($read.Rows['workspaces'])) { if ($w) { $workspaceName[[string]$w['id']] = [string]$w['name'] } }
        $result = ConvertTo-AACCosmosDBAssessment -Account $accounts -Resource $resources -Metric $metrics -Pricing @($read.Rows['pricing']) -Alert @($read.Rows['alerts']) -WorkspaceName $workspaceName -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $accountRows = @($r.Accounts | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, Account)
    $containerRows = @($r.Containers | Sort-Object -Property @{ Expression = { if ($null -eq $_.RU) { -1 } else { $_.RU } }; Descending = $true }, Account, Database, Container)
    $availabilities = @($r.Accounts | Where-Object { $null -ne $_.Availability -and $_.Requests } | ForEach-Object { $_.Availability })
    $worstAvailability = if ($availabilities.Count) { ($availabilities | Measure-Object -Minimum).Minimum } else { $null }
    $yesNo = @{ True = 'good'; False = 'warn' }
    $report = @{
        Subtitle = "Cosmos DB - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Time range' = "$TimeRange (storage: the latest value)"; Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC" }
        Status   = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Accounts) { 'No Cosmos DB account in scope.' } else { "$($stats.Accounts) account(s), $($stats.Containers) container(s), $('{0:N0}' -f $stats.RU) RU/s provisioned, $('{0:N2}' -f $stats.DataGB) GB: $($stats.High) high finding(s); $('{0:N0}' -f $stats.Throttled) request(s) rate limited; $($stats.Public) open to every network, $($stats.SingleRegion) in a single region" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Accounts; Label = 'accounts'; Tone = 'info'; Table = 'accounts' }
            @{ Value = '{0:N0}' -f $stats.Containers; Label = 'containers'; Tone = 'info'; Table = 'containers' }
            @{ Value = '{0:N0}' -f $stats.RU; Label = 'RU/s provisioned'; Tone = 'info'; Table = 'containers' }
            @{ Value = $(if ($null -eq $worstAvailability) { '-' } else { '{0:N2}' -f $worstAvailability }); Label = 'lowest availability %'; Tone = $(if ($null -eq $worstAvailability) { 'neutral' } elseif ($worstAvailability -ge 99.99) { 'good' } else { 'bad' }) }
            @{ Value = '{0:N0}' -f $stats.Throttled; Label = 'rate limited (429)'; Tone = $(if ($stats.Throttled) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Signal = 'Throttling' } }
            @{ Value = '{0:N0}' -f $stats.Public; Label = 'open to every network'; Tone = $(if ($stats.Public) { 'bad' } else { 'good' }); Table = 'posture'; Filters = @{ Network = 'Public' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Requests by status'; Kind = 'donut'; CenterLabel = 'requests'; Items = @(foreach ($k in @($r.StatusCodes.Keys)) { if ($r.StatusCodes[$k]) { @{ Label = $k; Value = $r.StatusCodes[$k]; Tone = @{ Success = 'good'; 'Throttled (429)' = 'bad'; 'Server (5xx)' = 'bad'; 'Client (4xx)' = 'warn'; 'Not found, conflict (404, 409, 412)' = 'neutral' }[$k] } } }) }
            @{ Title = 'APIs'; Items = @($r.Accounts | Group-Object -Property Api | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'accounts'; Column = 'Api'; Tone = 'violet' }
            @{ Title = 'Findings by signal'; Items = @($r.Findings | Group-Object -Property Signal | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Signal'; Tone = 'warn'; Console = $true }
        )
        Tabs     = @(
            @{ Name = 'Overview'; Badge = $stats.Accounts; Tone = 'info'; Note = 'Each account: availability, requests by status, rate limiting, request units and the busiest partition, latency, throughput and storage.' }
            @{ Name = 'Containers'; Badge = $stats.Containers; Tone = 'violet'; Note = 'Every database and container: partition key, throughput mode and RU/s, TTL, analytical store and indexing.' }
            @{ Name = 'Security & resilience'; Badge = $stats.Public + $stats.SingleRegion; Tone = $(if ($stats.Public) { 'bad' } else { 'good' }); Note = 'Each account''s network access, authentication, TLS, encryption, logs and Defender - and its regions, failover, zones, consistency and backup.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first.' }
        )
        Tables   = @(
            @{ Id = 'accounts'; Title = 'Overview'; Section = 'Overview'; Rows = $accountRows; Noun = 'accounts'; GroupBy = @('Subscription', 'ResourceGroup', 'Api', 'CapacityMode'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Api'; Label = 'API'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Availability'; Label = 'Availability %'; Type = 'number'; Format = 'N3'; Console = $true; Pdf = $true }
                    @{ Key = 'Requests'; Label = 'Requests'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Throttled'; Label = '429s'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'NormalizedRuMax'; Label = 'Busiest partition %'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'ProvisionedRU'; Label = 'Manual RU/s'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'AutoscaleMaxRU'; Label = 'Autoscale max RU/s'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'LatencyMs'; Label = 'Latency ms'; Type = 'number'; Format = 'N2' }
                    @{ Key = 'ServerErrors'; Label = 'Server errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'ClientErrors'; Label = 'Client errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'RequestUnits'; Label = 'Request units'; Type = 'number'; Sum = $true }
                    @{ Key = 'DataGB'; Label = 'Data GB'; Type = 'number'; Format = 'N2'; Sum = $true }
                    @{ Key = 'IndexGB'; Label = 'Index GB'; Type = 'number'; Format = 'N2'; Sum = $true }
                    @{ Key = 'Documents'; Label = 'Documents'; Type = 'number'; Sum = $true }
                    @{ Key = 'Databases'; Label = 'Databases'; Type = 'number'; Sum = $true }
                    @{ Key = 'Containers'; Label = 'Containers'; Type = 'number'; Sum = $true }
                    @{ Key = 'CapacityMode'; Label = 'Capacity'; Facet = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'containers'; Title = 'Containers'; Section = 'Containers'; Rows = $containerRows; Noun = 'containers'; GroupBy = @('Account', 'Database', 'ThroughputMode'); ConsoleLimit = 20
                Empty = 'No database or container.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Database'; Label = 'Database'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Container'; Label = 'Container'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'PartitionKey'; Label = 'Partition key'; Console = $true; Pdf = $true }
                    @{ Key = 'ThroughputMode'; Label = 'Throughput'; Type = 'badge'; Tones = @{ Autoscale = 'good'; Manual = 'info'; 'Shared database' = 'violet'; Serverless = 'neutral' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'RU'; Label = 'RU/s'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'DefaultTtl'; Label = 'Default TTL'; Type = 'number' }
                    @{ Key = 'AnalyticalStore'; Label = 'Analytical store'; Facet = $true }
                    @{ Key = 'IndexingMode'; Label = 'Indexing'; Facet = $true }
                    @{ Key = 'Api'; Label = 'API'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'posture'; Title = 'Security & resilience'; Section = 'Security & resilience'; Rows = $accountRows; Noun = 'accounts'; GroupBy = @('Network', 'Consistency', 'Backup'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Network'; Label = 'Network'; Type = 'badge'; Tones = @{ Private = 'good'; Firewall = 'info'; Public = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LocalAuth'; Label = 'Keys allowed'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'MinTls'; Label = 'Min TLS'; Facet = $true; Console = $true }
                    @{ Key = 'RegionCount'; Label = 'Regions'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'AutomaticFailover'; Label = 'Auto failover'; Type = 'badge'; Tones = $yesNo; Facet = $true; Console = $true }
                    @{ Key = 'ZoneRedundant'; Label = 'Zones'; Type = 'badge'; Tones = $yesNo; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Consistency'; Label = 'Consistency'; Facet = $true; Console = $true }
                    @{ Key = 'Backup'; Label = 'Backup'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Regions'; Label = 'Region names' }
                    @{ Key = 'MultiRegionWrites'; Label = 'Multi-region writes'; Facet = $true }
                    @{ Key = 'BackupRedundancy'; Label = 'Backup storage'; Facet = $true }
                    @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Type = 'number' }
                    @{ Key = 'Encryption'; Label = 'Encryption'; Facet = $true }
                    @{ Key = 'LogsTo'; Label = 'Logs to'; Facet = $true }
                    @{ Key = 'Defender'; Label = 'Defender'; Type = 'badge'; Tones = @{ On = 'good'; Off = 'warn' }; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Finding', 'Severity', 'Account'); ConsoleLimit = 20
                Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Database'; Label = 'Database' }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-View Container returns every container with its throughput; -TimeRange 7d looks further back; -Name or -ResourceGroupName narrows it; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Container' { $containerRows } 'Finding' { $r.Findings } default { $accountRows } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
