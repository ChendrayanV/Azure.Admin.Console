function Invoke-AACStorageAccountAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses storage accounts across subscriptions - what Azure Monitor's
        Storage accounts workbook shows (transactions, latency, errors by
        response type, capacity by service) plus availability, throttling,
        security posture, data protection and cost - as a heat map, findings,
        a Spectre.Console view, objects, and CSV, PDF and interactive HTML
        reports.
    .DESCRIPTION
        Read-only (Reader is enough):
          Resource Graph   the accounts, the Defender for Storage plan and its
                           alerts
          metrics          per account over -TimeRange - the workbook's
                           Overview tab: Transactions, SuccessE2ELatency,
                           SuccessServerLatency, Transactions by ResponseType,
                           plus Availability, Ingress and Egress
          capacity         the workbook's Capacity tab, the latest value:
                           UsedCapacity, BlobCapacity (with BlobCount and
                           ContainerCount), FileCapacity (and FileShareCount),
                           QueueCapacity and TableCapacity - capacity is
                           reported hourly to daily, so it is always read over
                           at least the last two days
          settings         blob and container soft delete, versioning, change
                           feed, point-in-time restore, file share soft
                           delete, lifecycle rules and where the blob logs go

        Response types are grouped: Success, Throttling (ClientThrottling*,
        ServerBusy*), Server (ServerTimeout, ServerOther), Authorization
        (Authorization, Authentication), Network (Network, ClientTimeout) and
        Client (ClientOther - mostly 404 and 409, often normal: they don't
        count as errors).

        Findings (High, Medium, Low):
          health      availability under 99.9%, throttling, server errors,
                      authorization failures, network errors, slow server
                      responses, time lost between client and service
          security    HTTP allowed, TLS below 1.2, anonymous blob access, open
                      to every network, shared key access, keys not rotated
                      in 90 days, no key or SAS expiration policy, cross-
                      tenant replication, no blob logs, Defender off or
                      alerting
          protection  LRS only, blob, container and file share soft delete
                      off (or under 7 days), versioning off
          cost        general-purpose v1 or legacy Blob storage accounts, no
                      lifecycle rules, idle accounts, hot tier with little
                      activity

        The heat map scores each account 0-100 for availability, errors,
        throttling, latency, security, protection and cost - the 40 worst at
        the prompt and in the reports; clicking a cell in the HTML lists its
        findings. The reports' tabs follow the workbook - Overview and
        Capacity - then Security & protection and Findings.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Account (default) or Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only accounts with these names; wildcards work.
    .PARAMETER TimeRange
        How far back the metrics go: 1h, 4h (the workbook's default), 12h, 1d
        (default), 3d, 7d, 14d or 30d.
    .PARAMETER View
        Account or Finding: what is returned and written to -CsvPath.
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
        Invoke-AACStorageAccountAssessment
        Every storage account's health, capacity, posture and findings over the last day.
    .EXAMPLE
        Invoke-AACStorageAccountAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\out\Storage.html -PdfPath .\out\Storage.pdf
        A week of a workload's storage accounts, as reports.
    .EXAMPLE
        Invoke-AACStorageAccountAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
        The security findings, to fix.
    .EXAMPLE
        Invoke-AACStorageAccountAssessment -NoDisplay | Sort-Object -Property UsedGB -Descending | Select-Object -First 10 -Property Account, UsedGB, BlobGB, FileGB, AccessTier, LifecycleRules
        The ten biggest accounts, and whether lifecycle rules keep their cost down.
    .OUTPUTS
        AAC.StorageAccountAssessment or AAC.StorageAccountFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.StorageAccountAssessment', 'AAC.StorageAccountFinding')]
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

        [ValidateSet('Account', 'Finding')]
        [string] $View = 'Account',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Storage account assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # TimeRange -> hours and the metric grain (an interval Azure Monitor accepts).
    $range = @{ '1h' = @(1, 'PT5M'); '4h' = @(4, 'PT15M'); '12h' = @(12, 'PT30M'); '1d' = @(24, 'PT1H'); '3d' = @(72, 'PT6H'); '7d' = @(168, 'PT6H'); '14d' = @(336, 'PT12H'); '30d' = @(720, 'P1D') }[$TimeRange]
    $end = [datetime]::UtcNow
    $span = { param([int] $Hours) "$($end.AddHours(-$Hours).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))" }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Hours = $range[0]; Timespan = & $span $range[0]; Interval = $range[1]
        # Capacity is emitted hourly (blob capacity daily): at least two days back, hourly, for the latest value.
        CapacityTimespan = & $span ([Math]::Max(48, $range[0])); ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Storage account assessment' -Color 'deepskyblue1' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the storage accounts and Defender (Resource Graph)'
        $read = Invoke-AACGraphBatch -Query (Get-AACStorageAccountQuery -ResourceGroupName $request.ResourceGroupName) -SubscriptionId $scope.GraphScope -AllowFailure @('pricing', 'alerts', 'workspaces')
        $accounts = @($read.Rows['accounts'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $request.Name.Count -or @($request.Name | Where-Object { $n -like $_ }).Count) })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} storage account(s)' -f $accounts.Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        # Which services each account's kind has: blob (all but FileStorage), file, queue and table (general purpose).
        $services = foreach ($a in $accounts) {
            $kind = [string]$a['kind']
            @{ Id = [string]$a['id']; Blob = $kind -ne 'FileStorage'; File = $kind -in 'StorageV2', 'Storage', 'FileStorage'; QueueTable = $kind -in 'StorageV2', 'Storage' }
        }
        $services = @($services)

        $overview = foreach ($a in $services) {
            @{ Id = $a.Id; Key = 'Core'; Metric = @('Transactions', 'Availability', 'SuccessE2ELatency', 'SuccessServerLatency', 'Ingress', 'Egress'); Aggregation = @('Total', 'Average'); Filter = '' }
            @{ Id = $a.Id; Key = 'Responses'; Metric = @('Transactions'); Aggregation = @('Total'); Filter = "ResponseType eq '*'" }
        }
        $capacity = foreach ($a in $services) {
            @{ Id = $a.Id; Key = 'Capacity'; Metric = @('UsedCapacity'); Aggregation = @('Average'); Filter = '' }
            if ($a.Blob) { @{ Id = "$($a.Id)/blobServices/default"; Key = 'Capacity'; Metric = @('BlobCapacity', 'BlobCount', 'ContainerCount'); Aggregation = @('Average'); Filter = '' } }
            if ($a.File) { @{ Id = "$($a.Id)/fileServices/default"; Key = 'Capacity'; Metric = @('FileCapacity', 'FileShareCount'); Aggregation = @('Average'); Filter = '' } }
            if ($a.QueueTable) {
                @{ Id = "$($a.Id)/queueServices/default"; Key = 'Capacity'; Metric = @('QueueCapacity'); Aggregation = @('Average'); Filter = '' }
                @{ Id = "$($a.Id)/tableServices/default"; Key = 'Capacity'; Metric = @('TableCapacity'); Aggregation = @('Average'); Filter = '' }
            }
        }
        $overview = @($overview); $capacity = @($capacity)
        $settingCount = 0
        foreach ($a in $services) { if ($a.Blob) { $settingCount += 3 }; if ($a.File) { $settingCount += 1 } }
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $overview.Count + $capacity.Count + $settingCount)) -Description 'Reading metrics, capacity and data protection settings'
        $tick = { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        $metrics = Read-AACNetworkHealthMetric -Call $overview -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        $capacityRead = Read-AACNetworkHealthMetric -Call $capacity -Timespan $request.CapacityTimespan -Interval 'PT1H' -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        $settings = Read-AACStorageAccountSetting -Account @($services | ForEach-Object { @{ Id = $_.Id; Blob = $_.Blob; File = $_.File } }) -ThrottleLimit $request.ThrottleLimit -OnProgress $tick
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read metrics, capacity and settings for {0:N0} account(s)' -f $accounts.Count)
        $failedMetrics = @($accounts | Where-Object { $m = $metrics[[string]$_['id']]; $m -and $m['Core'] -and $m['Core'].Error }).Count
        if ($failedMetrics) { $notices.Add("Metrics couldn't be read for $failedMetrics account(s) - their health is left blank (see MetricsError).") }

        $workspaceName = @{}
        foreach ($w in @($read.Rows['workspaces'])) { if ($w) { $workspaceName[[string]$w['id']] = [string]$w['name'] } }
        $result = ConvertTo-AACStorageAccountAssessment -Account $accounts -Metric $metrics -Capacity $capacityRead -Setting $settings -Pricing @($read.Rows['pricing']) -Alert @($read.Rows['alerts']) -WorkspaceName $workspaceName -SubscriptionName $scope.Names -Hours $request.Hours
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $accounts = @($r.Accounts | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, Account)
    $availabilities = @($r.Accounts | Where-Object { $null -ne $_.Availability -and $_.Transactions } | ForEach-Object { $_.Availability })
    $worstAvailability = if ($availabilities.Count) { ($availabilities | Measure-Object -Minimum).Minimum } else { $null }
    $sumOf = { param([string] $Property) $v = 0.0; foreach ($a in $r.Accounts) { if ($null -ne $a.$Property) { $v += [double]$a.$Property } }; [Math]::Round($v, 1) }
    $yesNo = @{ True = 'good'; False = 'warn' }
    $report = @{
        Subtitle = "Storage accounts - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Time range' = "$TimeRange (capacity: the latest value)"; Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC" }
        Status   = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Accounts) { 'No storage account in scope.' } else { "$($stats.Accounts) account(s), $('{0:N2}' -f $stats.UsedTB) TB, $('{0:N0}' -f $stats.Transactions) transaction(s): $($stats.High) high finding(s); $('{0:N0}' -f $stats.Throttled) throttled, $('{0:N0}' -f $stats.Failed) failed; $($stats.Public) open to every network, $($stats.NoSoftDelete) without blob soft delete" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Accounts; Label = 'storage accounts'; Tone = 'info'; Table = 'accounts' }
            @{ Value = '{0:N2}' -f $stats.UsedTB; Label = 'TB used'; Tone = 'info'; Table = 'capacity' }
            @{ Value = $(if ($null -eq $worstAvailability) { '-' } else { '{0:N2}' -f $worstAvailability }); Label = 'lowest availability %'; Tone = $(if ($null -eq $worstAvailability) { 'neutral' } elseif ($worstAvailability -ge 99.9) { 'good' } else { 'bad' }) }
            @{ Value = '{0:N0}' -f $stats.Throttled; Label = 'throttled requests'; Tone = $(if ($stats.Throttled) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Signal = 'Throttling' } }
            @{ Value = '{0:N0}' -f $stats.Public; Label = 'open to every network'; Tone = $(if ($stats.Public) { 'bad' } else { 'good' }); Table = 'protection'; Filters = @{ Network = 'Public' } }
            @{ Value = '{0:N0}' -f $stats.NoSoftDelete; Label = 'no blob soft delete'; Tone = $(if ($stats.NoSoftDelete) { 'warn' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'Blob soft delete off' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Requests by response type'; Kind = 'donut'; CenterLabel = 'requests'; Items = @(foreach ($k in @($r.ResponseTypes.Keys)) { if ($r.ResponseTypes[$k]) { @{ Label = $k; Value = $r.ResponseTypes[$k]; Tone = @{ Success = 'good'; Throttling = 'bad'; Server = 'bad'; Authorization = 'bad'; Network = 'warn'; 'Client (404, 409...)' = 'neutral' }[$k] } } }) }
            @{ Title = 'Capacity by service (GB)'; Items = @(@{ Label = 'Blob'; Value = & $sumOf 'BlobGB' }, @{ Label = 'File'; Value = & $sumOf 'FileGB' }, @{ Label = 'Queue'; Value = & $sumOf 'QueueGB' }, @{ Label = 'Table'; Value = & $sumOf 'TableGB' } | Where-Object { $_.Value }); Tone = 'info'; Table = 'capacity' }
            @{ Title = 'Redundancy'; Items = @($r.Accounts | Group-Object -Property Redundancy | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(unknown)' }); Value = $_.Count; Filter = $_.Name } }); Table = 'protection'; Column = 'Redundancy'; Tone = 'violet' }
        )
        Tabs     = @(
            @{ Name = 'Overview'; Badge = $stats.Accounts; Tone = 'info'; Note = 'The workbook''s Overview tab: transactions, latency end to end and on the server, and errors by response type - plus availability and traffic.' }
            @{ Name = 'Capacity'; Badge = $stats.Accounts; Tone = 'violet'; Note = 'The workbook''s Capacity tab: used capacity and blob, file, queue and table capacity (the latest value), with blob, container and share counts.' }
            @{ Name = 'Security & protection'; Badge = $stats.Public + $stats.Anonymous; Tone = $(if ($stats.Public -or $stats.Anonymous) { 'bad' } else { 'good' }); Note = 'Each account''s security settings, redundancy, soft delete, versioning, lifecycle rules and logs.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first.' }
        )
        Tables   = @(
            @{ Id = 'accounts'; Title = 'Overview'; Section = 'Overview'; Rows = $accounts; Noun = 'accounts'; GroupBy = @('Subscription', 'ResourceGroup', 'Kind', 'Redundancy'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Availability'; Label = 'Availability %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'Transactions'; Label = 'Transactions'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'E2ELatencyMs'; Label = 'E2E latency ms'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'ServerLatencyMs'; Label = 'Server latency ms'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'ErrorRate'; Label = 'Error %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'Throttled'; Label = 'Throttled'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ServerErrors'; Label = 'Server errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'AuthErrors'; Label = 'Auth errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'NetworkErrors'; Label = 'Network errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'ClientErrors'; Label = 'Client (404, 409...)'; Type = 'number'; Sum = $true }
                    @{ Key = 'ResponseTypes'; Label = 'Top failures'; Type = 'wide' }
                    @{ Key = 'IngressGB'; Label = 'Ingress GB'; Type = 'number'; Format = 'N2'; Sum = $true }
                    @{ Key = 'EgressGB'; Label = 'Egress GB'; Type = 'number'; Format = 'N2'; Sum = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'capacity'; Title = 'Capacity'; Section = 'Capacity'; Rows = @($r.Accounts | Sort-Object -Property @{ Expression = { if ($null -eq $_.UsedGB) { -1 } else { $_.UsedGB } }; Descending = $true }); Noun = 'accounts'; GroupBy = @('Subscription', 'AccessTier', 'Kind'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'UsedGB'; Label = 'Used GB'; Type = 'number'; Format = 'N2'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'BlobGB'; Label = 'Blob GB'; Type = 'number'; Format = 'N2'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'FileGB'; Label = 'File GB'; Type = 'number'; Format = 'N2'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'QueueGB'; Label = 'Queue GB'; Type = 'number'; Format = 'N2'; Sum = $true; Pdf = $true }
                    @{ Key = 'TableGB'; Label = 'Table GB'; Type = 'number'; Format = 'N2'; Sum = $true; Pdf = $true }
                    @{ Key = 'Blobs'; Label = 'Blobs'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'Containers'; Label = 'Containers'; Type = 'number'; Sum = $true }
                    @{ Key = 'FileShares'; Label = 'File shares'; Type = 'number'; Sum = $true }
                    @{ Key = 'AccessTier'; Label = 'Access tier'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LifecycleRules'; Label = 'Lifecycle rules'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'protection'; Title = 'Security & protection'; Section = 'Security & protection'; Rows = $accounts; Noun = 'accounts'; GroupBy = @('Network', 'Redundancy', 'MinTls', 'Defender'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Account'; Label = 'Account'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Network'; Label = 'Network'; Type = 'badge'; Tones = @{ Private = 'good'; Firewall = 'info'; Public = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'MinTls'; Label = 'Min TLS'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'BlobAnonymousAccess'; Label = 'Anonymous blobs'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'SharedKeyAccess'; Label = 'Shared keys'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Redundancy'; Label = 'Redundancy'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'BlobSoftDeleteDays'; Label = 'Blob soft delete days'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'ContainerSoftDeleteDays'; Label = 'Container soft delete days'; Type = 'number'; Pdf = $true }
                    @{ Key = 'Versioning'; Label = 'Versioning'; Type = 'badge'; Tones = $yesNo; Facet = $true; Console = $true }
                    @{ Key = 'ShareSoftDeleteDays'; Label = 'Share soft delete days'; Type = 'number' }
                    @{ Key = 'ChangeFeed'; Label = 'Change feed'; Facet = $true }
                    @{ Key = 'PointInTimeRestore'; Label = 'Point-in-time restore'; Facet = $true }
                    @{ Key = 'HttpsOnly'; Label = 'HTTPS only'; Facet = $true }
                    @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Type = 'number' }
                    @{ Key = 'CrossTenantReplication'; Label = 'Cross-tenant replication'; Facet = $true }
                    @{ Key = 'Encryption'; Label = 'Encryption'; Facet = $true }
                    @{ Key = 'KeyAgeDays'; Label = 'Key age days'; Type = 'number' }
                    @{ Key = 'KeyExpiryPolicy'; Label = 'Key expiry policy' }
                    @{ Key = 'SasExpiryPolicy'; Label = 'SAS expiry policy' }
                    @{ Key = 'LogsTo'; Label = 'Blob logs to'; Facet = $true }
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
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-TimeRange 4h matches the workbook (7d looks further back); -Name or -ResourceGroupName narrows it; -View Finding returns the findings; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = if ($View -eq 'Finding') { @($r.Findings) } else { $accounts }
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
