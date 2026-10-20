function Invoke-AACServiceBusAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses Azure Service Bus namespaces across subscriptions - health,
        capacity, every queue, topic and subscription's messages (active,
        dead-lettered, scheduled), security, resilience and cost - as a heat
        map, findings, a Spectre.Console view, objects, and CSV, PDF and
        interactive HTML reports.
    .DESCRIPTION
        Read-only (Reader is enough):
          Resource Graph    the namespaces: tier, messaging units, TLS, local
                            (SAS) authentication, public network access, zone
                            redundancy, private endpoints, encryption
          Resource Manager  each namespace's queues, topics and their
                            subscriptions (message counts and sizes as they
                            are now), network rules, SAS rules, geo-disaster
                            recovery alias, and where its logs go
          metrics           over -TimeRange: IncomingRequests,
                            SuccessfulRequests, ServerErrors, UserErrors,
                            ThrottledRequests, IncomingMessages,
                            OutgoingMessages - and for Premium,
                            NamespaceCpuUsage and NamespaceMemoryUsage

        Findings (High, Medium, Low):
          health      throttled requests, server errors, many client errors
                      (lost locks, missing entities)
          capacity    Premium CPU or memory close to the messaging units'
                      limit
          messages    dead-lettered and transfer dead-lettered messages,
                      entities filling up (sends fail at 100%), entities not
                      active, active backlogs, topics with no subscription,
                      expired messages dropped instead of dead-lettered
          security    TLS below 1.2, SAS keys allowed, more than one
                      namespace-wide Manage key, open to every network, no
                      logs to Log Analytics
          resilience  Premium not zone redundant, no geo-disaster recovery,
                      Basic tier
          cost        more messaging units than needed, no requests in the
                      period, queues and topics unused for 30 days

        The heat map scores each namespace 0-100 for health, capacity,
        messages, security, resilience and cost - the 40 worst at the prompt
        and in the reports; clicking a cell in the HTML lists its findings.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Namespace (default), Entity or Finding.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups.
    .PARAMETER Name
        Only namespaces with these names; wildcards work.
    .PARAMETER TimeRange
        How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
        or 30d. Message counts are always as they are now.
    .PARAMETER View
        Namespace, Entity or Finding: what is returned and written to -CsvPath.
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
        Invoke-AACServiceBusAssessment
        Every namespace's health, messages, posture and findings over the last day.
    .EXAMPLE
        Invoke-AACServiceBusAssessment -View Entity -NoDisplay | Where-Object DeadLetters | Sort-Object -Property DeadLetters -Descending
        The queues and subscriptions with dead-lettered messages, the most first.
    .EXAMPLE
        Invoke-AACServiceBusAssessment -ResourceGroupName 'rg-integration' -TimeRange 7d -HtmlPath .\out\ServiceBus.html -PdfPath .\out\ServiceBus.pdf
        A week of a workload's namespaces, as reports.
    .EXAMPLE
        Invoke-AACServiceBusAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
        The security findings, to fix.
    .OUTPUTS
        AAC.ServiceBusAssessment, AAC.ServiceBusEntity or AAC.ServiceBusFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ServiceBusAssessment', 'AAC.ServiceBusEntity', 'AAC.ServiceBusFinding')]
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

        [ValidateSet('Namespace', 'Entity', 'Finding')]
        [string] $View = 'Namespace',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Service Bus assessment',

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
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ }); Name = @($Name | Where-Object { $_ })
        Timespan = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"; Interval = $range[1]; ThrottleLimit = $ThrottleLimit
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Service Bus assessment' -Color 'darkorange' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'scope' -Indeterminate -Description 'Finding the subscriptions'
        $scope = Resolve-AACScope -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId
        Update-AACProgress -Id 'scope' -Complete -Description "Scope: $($scope.Label)"

        Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the Service Bus namespaces (Resource Graph)'
        $read = Invoke-AACGraphBatch -Query (Get-AACServiceBusQuery -ResourceGroupName $request.ResourceGroupName) -SubscriptionId $scope.GraphScope -AllowFailure @('workspaces')
        $namespaces = @($read.Rows['namespaces'] | Where-Object { $n = [string]$_['name']; $null -ne $_ -and (-not $request.Name.Count -or @($request.Name | Where-Object { $n -like $_ }).Count) })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} namespace(s)' -f $namespaces.Count)
        $notices = [System.Collections.Generic.List[string]]::new()
        foreach ($key in @($read.Errors.Keys | Sort-Object)) { $notices.Add("The $key couldn't be read: $($read.Errors[$key] -replace '\s+', ' ')") }

        $ids = @($namespaces | ForEach-Object { [string]$_['id'] })
        $calls = foreach ($n in $namespaces) {
            @{ Id = [string]$n['id']; Key = 'Core'; Metric = @('IncomingRequests', 'SuccessfulRequests', 'ServerErrors', 'UserErrors', 'ThrottledRequests', 'IncomingMessages', 'OutgoingMessages'); Aggregation = @('Total'); Filter = '' }
            if ([string]$n['tier'] -eq 'Premium') { @{ Id = [string]$n['id']; Key = 'Premium'; Metric = @('NamespaceCpuUsage', 'NamespaceMemoryUsage'); Aggregation = @('Maximum'); Filter = '' } }
        }
        $calls = @($calls)
        Update-AACProgress -Id 'entities' -Indeterminate -Description "Reading the queues, topics, subscriptions and settings of $($ids.Count) namespace(s)"
        $entities = Read-AACServiceBusEntity -NamespaceId $ids -ThrottleLimit $request.ThrottleLimit
        Update-AACProgress -Id 'entities' -Complete -Description ('Read the entities and settings of {0:N0} namespace(s)' -f $ids.Count)
        Update-AACProgress -Id 'metrics' -Total ([Math]::Max(1, $calls.Count)) -Description 'Reading the metrics (Azure Monitor)'
        $metrics = Read-AACNetworkHealthMetric -Call $calls -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
        Update-AACProgress -Id 'metrics' -Complete -Description ('Read the metrics of {0:N0} namespace(s)' -f $ids.Count)
        $failedMetrics = @($ids | Where-Object { $m = $metrics[$_]; $m -and $m['Core'] -and $m['Core'].Error }).Count
        if ($failedMetrics) { $notices.Add("Metrics couldn't be read for $failedMetrics namespace(s) - their health is left blank (see MetricsError).") }
        $unread = @($ids | Where-Object { $e = $entities[$_]; $e.Queues -and $e.Queues['Error'] -and $e.Topics -and $e.Topics['Error'] }).Count
        if ($unread) { $notices.Add("The queues and topics of $unread namespace(s) couldn't be read - their messages are left out.") }

        $workspaceName = @{}
        foreach ($w in @($read.Rows['workspaces'])) { if ($w) { $workspaceName[[string]$w['id']] = [string]$w['name'] } }
        $result = ConvertTo-AACServiceBusAssessment -Namespace $namespaces -Entity $entities -Metric $metrics -WorkspaceName $workspaceName -SubscriptionName $scope.Names
        @{ Result = $result; Scope = $scope; Notices = $notices.ToArray() }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $namespaceRows = @($r.Namespaces | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, Namespace)
    $entityRows = @($r.Entities | Sort-Object -Property @{ Expression = { $_.DeadLetters + $_.TransferDeadLetters }; Descending = $true }, @{ Expression = { $_.ActiveMessages }; Descending = $true }, Namespace, Entity)
    $yesNo = @{ True = 'good'; False = 'warn' }
    $report = @{
        Subtitle = "Service Bus - last $TimeRange"
        Facts    = [ordered]@{ Scope = $state.Scope.Label; 'Time range' = "$TimeRange (messages: as they are now)"; Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC" }
        Status   = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline = $(if (-not $stats.Namespaces) { 'No Service Bus namespace in scope.' } else { "$($stats.Namespaces) namespace(s), $($stats.Entities) queue(s), topic(s) and subscription(s): $($stats.High) high finding(s); $('{0:N0}' -f $stats.DeadLetters) dead-lettered and $('{0:N0}' -f $stats.Active) active message(s); $('{0:N0}' -f $stats.Throttled) throttled request(s); $($stats.Public) open to every network, $($stats.LocalAuth) allowing SAS keys" })
        Tiles    = @(
            @{ Value = '{0:N0}' -f $stats.Namespaces; Label = 'namespaces'; Tone = 'info'; Table = 'namespaces' }
            @{ Value = '{0:N0}' -f $stats.Entities; Label = 'queues, topics, subscriptions'; Tone = 'info'; Table = 'entities' }
            @{ Value = '{0:N0}' -f $stats.Active; Label = 'active messages'; Tone = 'info'; Table = 'entities' }
            @{ Value = '{0:N0}' -f $stats.DeadLetters; Label = 'dead-lettered'; Tone = $(if ($stats.DeadLetters) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'Dead-lettered messages' } }
            @{ Value = '{0:N0}' -f $stats.Throttled; Label = 'throttled requests'; Tone = $(if ($stats.Throttled) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Finding = 'Requests throttled' } }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } })
        HeatMaps = @($(if (@($r.HeatMap.Rows).Count) { $r.HeatMap }))
        Charts   = @(
            @{ Title = 'Messages waiting'; Kind = 'donut'; CenterLabel = 'messages'; Items = @(foreach ($k in @($r.Messages.Keys)) { if ($r.Messages[$k]) { @{ Label = $k; Value = $r.Messages[$k]; Tone = @{ Active = 'info'; 'Dead-lettered' = 'bad'; Scheduled = 'neutral'; 'Transfer dead-lettered' = 'warn' }[$k] } } }) }
            @{ Title = 'Tiers'; Items = @($r.Namespaces | Group-Object -Property Tier | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $(if ($_.Name) { $_.Name } else { '(unknown)' }); Value = $_.Count; Filter = $_.Name } }); Table = 'namespaces'; Column = 'Tier'; Tone = 'violet' }
            @{ Title = 'Findings by signal'; Items = @($r.Findings | Group-Object -Property Signal | Sort-Object -Property Count -Descending | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Signal'; Tone = 'warn'; Console = $true }
        )
        Tabs     = @(
            @{ Name = 'Overview'; Badge = $stats.Namespaces; Tone = 'info'; Note = 'Each namespace: requests, errors and throttling over the period, Premium CPU and memory, and its messages now.' }
            @{ Name = 'Entities'; Badge = $stats.Entities; Tone = $(if ($stats.DeadLetters) { 'bad' } else { 'violet' }); Note = 'Every queue, topic and subscription: active, dead-lettered and scheduled messages, size against its maximum, and when it was last used.' }
            @{ Name = 'Security & resilience'; Badge = $stats.Public + $stats.LocalAuth; Tone = $(if ($stats.Public) { 'bad' } else { 'good' }); Note = 'Each namespace''s TLS, authentication, network access, encryption, logs, zone redundancy and geo-disaster recovery.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to fix, worst first.' }
        )
        Tables   = @(
            @{ Id = 'namespaces'; Title = 'Overview'; Section = 'Overview'; Rows = $namespaceRows; Noun = 'namespaces'; GroupBy = @('Subscription', 'ResourceGroup', 'Tier'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Namespace'; Label = 'Namespace'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Score'; Label = 'Score'; Type = 'score'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Tier'; Label = 'Tier'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Requests'; Label = 'Requests'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ErrorRate'; Label = 'Error %'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'Throttled'; Label = 'Throttled'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ActiveMessages'; Label = 'Active'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLetters'; Label = 'Dead-lettered'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'FullestPct'; Label = 'Fullest entity %'; Type = 'number'; Format = 'N1'; Console = $true }
                    @{ Key = 'CpuMax'; Label = 'CPU max %'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'MemoryMax'; Label = 'Memory max %'; Type = 'number'; Format = 'N1' }
                    @{ Key = 'MessagingUnits'; Label = 'Messaging units'; Type = 'number' }
                    @{ Key = 'Queues'; Label = 'Queues'; Type = 'number'; Sum = $true }
                    @{ Key = 'Topics'; Label = 'Topics'; Type = 'number'; Sum = $true }
                    @{ Key = 'Subscriptions'; Label = 'Subscriptions'; Type = 'number'; Sum = $true }
                    @{ Key = 'IncomingMessages'; Label = 'Messages in'; Type = 'number'; Sum = $true }
                    @{ Key = 'OutgoingMessages'; Label = 'Messages out'; Type = 'number'; Sum = $true }
                    @{ Key = 'ServerErrors'; Label = 'Server errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'UserErrors'; Label = 'Client errors'; Type = 'number'; Sum = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'entities'; Title = 'Entities'; Section = 'Entities'; Rows = $entityRows; Noun = 'entities'; GroupBy = @('Namespace', 'Type', 'Status'); ConsoleLimit = 20
                Empty = 'No queue, topic or subscription.'; EmptyStatus = 'Info'
                Columns = @(
                    @{ Key = 'Namespace'; Label = 'Namespace'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Entity'; Label = 'Entity'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Type'; Label = 'Type'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = @{ Active = 'good'; Disabled = 'bad'; SendDisabled = 'warn'; ReceiveDisabled = 'warn' }; Facet = $true; Console = $true }
                    @{ Key = 'ActiveMessages'; Label = 'Active'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLetters'; Label = 'Dead-lettered'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'TransferDeadLetters'; Label = 'Transfer DLQ'; Type = 'number'; Sum = $true }
                    @{ Key = 'Scheduled'; Label = 'Scheduled'; Type = 'number'; Sum = $true }
                    @{ Key = 'UsedPct'; Label = 'Used %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'SizeMB'; Label = 'Size MB'; Type = 'number'; Format = 'N2' }
                    @{ Key = 'MaxSizeMB'; Label = 'Max MB'; Type = 'number' }
                    @{ Key = 'Subscriptions'; Label = 'Subscriptions'; Type = 'number' }
                    @{ Key = 'MaxDeliveryCount'; Label = 'Max deliveries'; Type = 'number' }
                    @{ Key = 'LockDuration'; Label = 'Lock' }
                    @{ Key = 'Sessions'; Label = 'Sessions'; Facet = $true }
                    @{ Key = 'DeadLetterOnExpiration'; Label = 'DLQ on expiry'; Type = 'badge'; Tones = $yesNo; Facet = $true }
                    @{ Key = 'ForwardTo'; Label = 'Forwards to' }
                    @{ Key = 'IdleDays'; Label = 'Idle days'; Type = 'number'; Console = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Sum = $true }
                ) }
            @{ Id = 'posture'; Title = 'Security & resilience'; Section = 'Security & resilience'; Rows = $namespaceRows; Noun = 'namespaces'; GroupBy = @('Network', 'Tier', 'LocalAuth'); ConsoleLimit = 15
                Columns = @(
                    @{ Key = 'Namespace'; Label = 'Namespace'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Network'; Label = 'Network'; Type = 'badge'; Tones = @{ Private = 'good'; Firewall = 'info'; Public = 'warn' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'MinTls'; Label = 'Min TLS'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LocalAuth'; Label = 'SAS keys'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'ManageKeys'; Label = 'Manage keys'; Type = 'number'; Console = $true }
                    @{ Key = 'PrivateEndpoints'; Label = 'Private endpoints'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'ZoneRedundant'; Label = 'Zone redundant'; Type = 'badge'; Tones = $yesNo; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'GeoDr'; Label = 'Geo-DR'; Facet = $true; Console = $true }
                    @{ Key = 'LogsTo'; Label = 'Logs to'; Facet = $true; Console = $true }
                    @{ Key = 'Encryption'; Label = 'Encryption'; Facet = $true }
                    @{ Key = 'Identity'; Label = 'Identity'; Facet = $true }
                    @{ Key = 'Tier'; Label = 'Tier'; Facet = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Finding', 'Severity', 'Namespace'); ConsoleLimit = 20
                Empty = 'Nothing to fix.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Namespace'; Label = 'Namespace'; Type = 'resource'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Entity'; Label = 'Entity'; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                ) }
        )
        Hint     = '-View Entity returns every queue, topic and subscription (Where-Object DeadLetters finds the dead letters); -TimeRange 7d looks further back; -Name or -ResourceGroupName narrows it; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Entity' { $entityRows } 'Finding' { $r.Findings } default { $namespaceRows } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
