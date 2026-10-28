function Show-AACServiceBusEntity {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows Service Bus queues and topics as you can see them - live
        message counts, dead-letters, subscriptions, configuration and, with
        access to the namespace, their metrics - whether your role is on the
        namespace or only on the entities.
    .DESCRIPTION
        Read-only. Works out what your sign-in can read, entity by entity:
          namespace role   Reader, Monitoring Reader or Data Owner on the
                           namespace: names can use wildcards (or be left out
                           to list every queue and topic), and each entity's
                           Azure Monitor metrics are read over -TimeRange
          entity role      Azure Service Bus Data Sender or Receiver on a
                           queue or topic: exact names only, live state only -
                           Service Bus publishes metrics on the namespace, so
                           an entity role can't read them. -Sample reads the
                           live counts a few times instead, for a short trend.

        Live state (Resource Manager): active, dead-lettered, scheduled,
        transfer and transfer dead-lettered messages, size against the
        maximum, status, when last used, each topic subscription's counts,
        and every setting (lock duration, max delivery count, TTL, sessions,
        duplicate detection, forwarding, partitioning, auto-delete).

        Metrics (namespace access): incoming, outgoing, completed and
        abandoned messages, requests, server and user errors, throttling,
        active, dead-lettered and scheduled messages over time, size, bytes,
        send latency - per queue or topic (Azure has none per subscription) -
        and a Premium namespace's CPU and memory.

        Findings: dead-letters, transfer dead-letters, entities filling up
        or not active, throttling, server errors, messages arriving with none
        received, a growing backlog, entities unused for 30 days, expired
        messages dropped - and entities you have no role on or that don't
        exist.

        -View sets what is returned (piped onward, -PassThru, -NoDisplay) and
        written to -CsvPath: Entity (default), Subscription, Metric, Sample,
        Finding or Access.
    .PARAMETER NamespaceId
        The namespace's full resource ID:
        /subscriptions/<id>/resourceGroups/<group>/providers/Microsoft.ServiceBus/namespaces/<name>.
        With only an entity role you can't look it up, so ask the platform
        team for it.
    .PARAMETER EntityName
        The queues or topics, by exact name. Wildcards - and leaving it out,
        to show them all - need read access on the namespace.
    .PARAMETER EntityKind
        Queue, Topic or Auto (default): Auto tries a queue, then a topic.
    .PARAMETER TimeRange
        How far back the metrics go: 1h, 4h, 12h, 1d (default), 3d, 7d, 14d
        or 30d. Message counts are always as they are now.
    .PARAMETER SkipMetrics
        Don't read metrics.
    .PARAMETER Sample
        Read the live counts this many times (2 to 120), -SampleInterval
        apart, for a backlog trend without metrics.
    .PARAMETER SampleInterval
        The time between samples (30 seconds by default; 5 seconds to 10
        minutes).
    .PARAMETER View
        Entity, Subscription, Metric, Sample, Finding or Access: what is
        returned and written to -CsvPath.
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
        Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders'
        One queue or topic: its live state, and its metrics if you can read the namespace.
    .EXAMPLE
        Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders-*' -TimeRange 7d -HtmlPath .\sb.html
        Every queue and topic starting orders-, with a week of metrics, as a tabbed report (namespace access).
    .EXAMPLE
        Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders' -Sample 10 -SampleInterval 00:00:30
        With an entity role only: ten reads, 30 seconds apart, show whether the backlog is growing.
    .EXAMPLE
        Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'events' -View Subscription -NoDisplay | Where-Object DeadLettered
        A topic's subscriptions with dead-lettered messages.
    .OUTPUTS
        AAC.ServiceBusLookup, AAC.ServiceBusLookupSubscription, AAC.ServiceBusLookupMetric, AAC.ServiceBusLookupSample, AAC.ServiceBusLookupFinding or AAC.ServiceBusLookupAccess, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ServiceBusLookup', 'AAC.ServiceBusLookupSubscription', 'AAC.ServiceBusLookupMetric', 'AAC.ServiceBusLookupSample', 'AAC.ServiceBusLookupFinding', 'AAC.ServiceBusLookupAccess')]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft\.ServiceBus/namespaces/[A-Za-z0-9-]+/?$')]
        [string] $NamespaceId,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $EntityName,

        [ValidateSet('Auto', 'Queue', 'Topic')]
        [string] $EntityKind = 'Auto',

        [ValidateSet('1h', '4h', '12h', '1d', '3d', '7d', '14d', '30d')]
        [string] $TimeRange = '1d',

        [switch] $SkipMetrics,

        [ValidateRange(2, 120)]
        [int] $Sample,

        [ValidateScript({ $_ -ge [timespan]::FromSeconds(5) -and $_ -le [timespan]::FromMinutes(10) })]
        [timespan] $SampleInterval = [timespan]::FromSeconds(30),

        [ValidateSet('Entity', 'Subscription', 'Metric', 'Sample', 'Finding', 'Access')]
        [string] $View = 'Entity',

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Service Bus entities',

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
        NamespaceId = $NamespaceId.TrimEnd('/'); EntityName = @($EntityName | Where-Object { $_ }); EntityKind = $EntityKind; SkipMetrics = [bool]$SkipMetrics
        Sample = $Sample; SampleInterval = $SampleInterval; ThrottleLimit = $ThrottleLimit
        Timespan = "$($end.AddHours(-$range[0]).ToString('yyyy-MM-ddTHH:mm:ssZ'))/$($end.ToString('yyyy-MM-ddTHH:mm:ssZ'))"; Interval = $range[1]
    }
    $namespace = ($request.NamespaceId -split '/')[-1]

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Service Bus entities' -Color 'darkorange' }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'read' -Indeterminate -Description "Reading $namespace and its entities as you"
        $read = Read-AACServiceBusEntityState -NamespaceId $request.NamespaceId -EntityName $request.EntityName -EntityKind $request.EntityKind -ThrottleLimit $request.ThrottleLimit
        $found = @($read.Entities | Where-Object { $_.Outcome -eq 'Read' })
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} of {1:N0} queue(s) and topic(s) - {2} access' -f $found.Count, @($read.Entities).Count, $read.Access.ToLowerInvariant())

        $metric = $null
        if (-not $request.SkipMetrics -and $found.Count) {
            $set = Get-AACServiceBusEntityMetricSet
            # A filter naming many entities gets long: ten to a request.
            $chunks = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $found.Count; $i += 10) { $chunks.Add(@($found[$i..([Math]::Min($i + 9, $found.Count - 1))])) }
            $calls = [System.Collections.Generic.List[hashtable]]::new()
            for ($c = 0; $c -lt $chunks.Count; $c++) {
                $filter = (@($chunks[$c] | ForEach-Object { "EntityName eq '$($_.Name -replace "'", "''")'" })) -join ' or '
                foreach ($g in $set.Entity) { $calls.Add(@{ Id = $request.NamespaceId; Key = "$($g.Key)#$c"; Metric = $g.Metric; Aggregation = $g.Aggregation; Filter = $filter }) }
            }
            $tier = if ($read.Namespace -is [System.Collections.IDictionary] -and $read.Namespace['sku'] -is [System.Collections.IDictionary]) { [string]$read.Namespace['sku']['name'] } else { '' }
            if ($tier -eq 'Premium') { $calls.Add(@{ Id = $request.NamespaceId; Key = $set.Premium.Key; Metric = $set.Premium.Metric; Aggregation = $set.Premium.Aggregation; Filter = '' }) }
            Update-AACProgress -Id 'metrics' -Total $calls.Count -Description 'Reading the metrics (Azure Monitor, on the namespace)'
            $all = Read-AACMetric -Call $calls.ToArray() -Timespan $request.Timespan -Interval $request.Interval -ThrottleLimit $request.ThrottleLimit -OnProgress { param($Done, $Total) Update-AACProgress -Id 'metrics' -Increment 1 }
            $metric = $all[$request.NamespaceId]
            $answered = @($metric.Values | Where-Object { -not $_.Error }).Count
            Update-AACProgress -Id 'metrics' -Complete -Description $(if ($answered) { "Read the metrics over the last $TimeRange" } elseif (@($metric.Values | Where-Object { [int]$_.Status -eq 403 }).Count) { 'Metrics: no permission on the namespace (live state only)' } else { 'Metrics could not be read' })
        }

        $samples = @()
        if ($request.Sample -and $found.Count) {
            Update-AACProgress -Id 'sample' -Total $request.Sample -Description ('Sampling the live counts {0} times, {1:N0}s apart' -f $request.Sample, $request.SampleInterval.TotalSeconds)
            $samples = @(Read-AACServiceBusEntitySample -NamespaceId $request.NamespaceId -Entity $found -Count $request.Sample -Interval $request.SampleInterval -ThrottleLimit $request.ThrottleLimit -OnSample { param($Number, $Count) if ($Number -gt 1) { Update-AACProgress -Id 'sample' -Increment 1 } })
            Update-AACProgress -Id 'sample' -Complete -Description ('Sampled the live counts {0} times' -f $request.Sample)
        }

        $result = ConvertTo-AACServiceBusLookup -State $read -NamespaceId $request.NamespaceId -Metric $metric -MetricMode $(if ($request.SkipMetrics) { 'Skipped' } else { 'Read' }) -Sample $samples
        @{ Result = $result; Access = $read.Access; Notices = @(@($read.Notices) + @($result.Notices)) }
    }

    # --- Report ------------------------------------------------------------------------------------------------
    $r = $state.Result
    $stats = $r.Stats
    $rank = Get-AACSeverityRank
    $unicode = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Unicode
    $entityRows = @($r.Entities | Sort-Object -Property @{ Expression = { $_.Access -eq 'None' } }, @{ Expression = { [long]$_.DeadLettered + [long]$_.TransferDeadLettered }; Descending = $true }, @{ Expression = { [long]$_.Active }; Descending = $true }, Entity)
    $readRows = @($entityRows | Where-Object Access -NE 'None')
    $subscriptionRows = @($r.Subscriptions | Sort-Object -Property @{ Expression = { $_.DeadLettered + $_.TransferDeadLettered }; Descending = $true }, Topic, Subscription)
    # Dead-letter: every queue and subscription that holds messages, one list.
    $deadRows = @(
        @($readRows | Where-Object Kind -EQ 'Queue') | ForEach-Object { [pscustomobject][ordered]@{ Entity = $_.Entity; Kind = 'Queue'; DeadLettered = $_.DeadLettered; TransferDeadLettered = $_.TransferDeadLettered; MaxDeliveryCount = $_.MaxDeliveryCount; DeadLetterOnExpiration = $_.DeadLetterOnExpiration; DeadLetterOnFilterError = $null; ForwardDeadLetteredTo = $_.ForwardDeadLetteredTo } }
        $subscriptionRows | ForEach-Object { [pscustomobject][ordered]@{ Entity = "$($_.Topic)/$($_.Subscription)"; Kind = 'Subscription'; DeadLettered = $_.DeadLettered; TransferDeadLettered = $_.TransferDeadLettered; MaxDeliveryCount = $_.MaxDeliveryCount; DeadLetterOnExpiration = $_.DeadLetterOnExpiration; DeadLetterOnFilterError = $_.DeadLetterOnFilterError; ForwardDeadLetteredTo = $_.ForwardDeadLetteredTo } }
    ) | Sort-Object -Property @{ Expression = { $_.DeadLettered + $_.TransferDeadLettered }; Descending = $true }, Entity
    $yesNo = @{ True = 'good'; False = 'warn' }
    $statusTones = @{ Active = 'good'; Disabled = 'bad'; SendDisabled = 'warn'; ReceiveDisabled = 'warn'; 'No role' = 'bad'; 'Not found' = 'warn'; Failed = 'bad' }
    $metricNote = switch ($r.MetricStatus) {
        'Read' { "Azure Monitor metrics of the namespace, split by entity, over the last $TimeRange. A topic's are the total of its subscriptions." }
        'No permission' { 'Metrics are published on the namespace: reading them needs Monitoring Reader (or Reader) there. An entity role shows the live state only.' }
        'Skipped' { 'Metrics were skipped (-SkipMetrics).' }
        default { 'No metrics could be read.' }
    }
    $report = @{
        Subtitle    = "Service Bus - $namespace"
        Facts       = [ordered]@{
            Namespace = $namespace; Access = $(if ($state.Access -eq 'Namespace') { 'Namespace (every entity, metrics)' } else { 'Entity role only (live state of the named entities)' })
            Metrics = $(if ($r.MetricStatus -eq 'Read') { "Read - last $TimeRange" } else { $r.MetricStatus }); Generated = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
        }
        Status      = $(if ($stats.High) { 'Failed' } elseif (@($r.Findings).Count) { 'Warning' } else { 'Success' })
        Headline    = $(if (-not $stats.Entities) { 'No queue or topic to show.' } else { "$($stats.Read) of $($stats.Entities) queue(s) and topic(s) read: $('{0:N0}' -f $stats.Active) active and $('{0:N0}' -f $stats.DeadLettered) dead-lettered message(s); $($stats.High) high finding(s)$(if ($stats.NotRead) { "; $($stats.NotRead) couldn't be read" })" })
        OverviewTab = 'Summary'
        Tiles       = @(
            @{ Value = '{0:N0}' -f $stats.Read; Label = 'entities read'; Tone = $(if ($stats.NotRead) { 'warn' } else { 'info' }); Table = 'entities' }
            @{ Value = '{0:N0}' -f $stats.Active; Label = 'active messages'; Tone = 'info'; Table = 'entities' }
            @{ Value = '{0:N0}' -f $stats.DeadLettered; Label = 'dead-lettered'; Tone = $(if ($stats.DeadLettered) { 'bad' } else { 'good' }); Table = 'deadletter' }
            @{ Value = '{0:N0}' -f $stats.Scheduled; Label = 'scheduled'; Tone = 'neutral'; Table = 'entities' }
            @{ Value = $(if ($r.MetricStatus -eq 'Read') { '{0:N0}' -f $stats.Throttled } else { '-' }); Label = 'throttled requests'; Tone = $(if ($stats.Throttled) { 'bad' } elseif ($r.MetricStatus -eq 'Read') { 'good' } else { 'neutral' }); Table = 'metrics' }
            @{ Value = '{0:N0}' -f $stats.High; Label = 'high findings'; Tone = $(if ($stats.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices     = @(
            @{ Status = 'Info'; Text = $(if ($state.Access -eq 'Namespace') { 'You can read the namespace: every queue and topic, and their metrics.' } else { 'You hold a role on entities, not on the namespace: the live state of the named entities is shown; metrics need the namespace.' }) }
            $state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }
        )
        Charts      = @(
            @{ Title = 'Messages waiting'; Kind = 'donut'; CenterLabel = 'messages'; Items = @(@{ Label = 'Active'; Value = $stats.Active; Tone = 'info' }, @{ Label = 'Dead-lettered'; Value = $stats.DeadLettered; Tone = 'bad' }, @{ Label = 'Scheduled'; Value = $stats.Scheduled; Tone = 'neutral' }) | Where-Object { $_.Value } }
            @{ Title = 'Dead-lettered by entity'; Items = @($deadRows | Where-Object { $_.DeadLettered + $_.TransferDeadLettered } | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Entity; Value = $_.DeadLettered + $_.TransferDeadLettered; Filter = $_.Entity } }); Table = 'deadletter'; Column = 'Entity'; Tone = 'bad'; Console = $true }
        )
        Tabs        = @(
            @{ Name = 'Live state'; Badge = $stats.Read; Tone = 'info'; Note = 'Each queue and topic as it is now. A topic''s message counts are the sum of its subscriptions''.' }
            @{ Name = 'Dead-letter'; Badge = $stats.DeadLettered; Tone = $(if ($stats.DeadLettered) { 'bad' } else { 'good' }); Note = 'Messages moved aside after Max delivery count, on expiry (when on), on a filter error (when on) or by the receiver. They stay until someone processes the dead-letter queue. Transfer DLQ holds messages that could not be auto-forwarded.' }
            @{ Name = 'Subscriptions'; Badge = $subscriptionRows.Count; Tone = 'violet'; Note = 'Each topic''s subscriptions: where a topic''s backlog and dead-letters are.' }
            @{ Name = 'Configuration'; Badge = $stats.Read; Tone = 'neutral'; Note = 'Every setting of each queue, topic and subscription.' }
            @{ Name = 'Metrics'; Badge = @($r.Metrics).Count + @($r.Samples).Count; Tone = $(if ($r.MetricStatus -eq 'Read') { 'info' } else { 'neutral' }); Note = "$metricNote$(if (@($r.Samples).Count) { ' The samples are live reads, a while apart.' })" }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($stats.High) { 'bad' } else { 'warn' }); Note = 'What to look at, worst first.' }
            @{ Name = 'What you can see'; Badge = @($r.Access).Count; Tone = $(if ($stats.NotRead) { 'warn' } else { 'good' }); Note = 'What this sign-in could read for each entity, and the role that would show the rest. An entity role (Data Sender or Receiver) reads the entity''s live state; metrics are published on the namespace and need Monitoring Reader (or Reader) there.' }
        )
        Tables      = @(
            @{ Id = 'entities'; Title = 'Live state'; Section = 'Live state'; Rows = $entityRows; Noun = 'entities'; GroupBy = @('Kind', 'Status', 'Access'); ConsoleLimit = 20
                Columns = @(
                    @{ Key = 'Entity'; Label = 'Entity'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Active'; Label = 'Active'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLettered'; Label = 'Dead-lettered'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scheduled'; Label = 'Scheduled'; Type = 'number'; Sum = $true; Console = $true }
                    @{ Key = 'TransferDeadLettered'; Label = 'Transfer DLQ'; Type = 'number'; Sum = $true }
                    @{ Key = 'Transfer'; Label = 'Transfer'; Type = 'number'; Sum = $true }
                    @{ Key = 'Messages'; Label = 'All messages'; Type = 'number'; Sum = $true }
                    @{ Key = 'Subscriptions'; Label = 'Subscriptions'; Type = 'number' }
                    @{ Key = 'UsedPct'; Label = 'Used %'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'SizeMB'; Label = 'Size MB'; Type = 'number'; Format = 'N2' }
                    @{ Key = 'MaxSizeMB'; Label = 'Max MB'; Type = 'number' }
                    @{ Key = 'ActiveTrend'; Label = 'Active trend'; Console = $unicode }
                    @{ Key = 'Incoming'; Label = 'In'; Type = 'number'; Sum = $true; Console = ($r.MetricStatus -eq 'Read') }
                    @{ Key = 'Outgoing'; Label = 'Out'; Type = 'number'; Sum = $true; Console = ($r.MetricStatus -eq 'Read') }
                    @{ Key = 'Throttled'; Label = 'Throttled'; Type = 'number'; Sum = $true }
                    @{ Key = 'LastAccessed'; Label = 'Last used'; Type = 'datetime'; Console = $true }
                    @{ Key = 'IdleDays'; Label = 'Idle days'; Type = 'number' }
                    @{ Key = 'Access'; Label = 'Access'; Facet = $true }
                    @{ Key = 'Metrics'; Label = 'Metrics'; Facet = $true }
                    @{ Key = 'Error'; Label = 'Why not read'; Type = 'wide' }
                ) }
            @{ Id = 'deadletter'; Title = 'Dead-letter'; Section = 'Dead-letter'; Rows = $deadRows; Noun = 'queues and subscriptions'; GroupBy = @('Kind'); ConsoleLimit = 15; NoConsole = (-not @($deadRows | Where-Object { $_.DeadLettered + $_.TransferDeadLettered }).Count)
                Columns = @(
                    @{ Key = 'Entity'; Label = 'Queue or subscription'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLettered'; Label = 'Dead-lettered'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'TransferDeadLettered'; Label = 'Transfer DLQ'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'MaxDeliveryCount'; Label = 'Max deliveries'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLetterOnExpiration'; Label = 'DLQ on expiry'; Type = 'badge'; Tones = $yesNo; Facet = $true; Console = $true }
                    @{ Key = 'DeadLetterOnFilterError'; Label = 'DLQ on filter error'; Facet = $true }
                    @{ Key = 'ForwardDeadLetteredTo'; Label = 'Dead-letters forwarded to' }
                ) }
            @{ Id = 'subscriptions'; Title = 'Subscriptions'; Section = 'Subscriptions'; Rows = $subscriptionRows; Noun = 'subscriptions'; GroupBy = @('Topic', 'Status'); ConsoleLimit = 20
                Columns = @(
                    @{ Key = 'Topic'; Label = 'Topic'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true }
                    @{ Key = 'Active'; Label = 'Active'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLettered'; Label = 'Dead-lettered'; Type = 'number'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Scheduled'; Label = 'Scheduled'; Type = 'number'; Sum = $true }
                    @{ Key = 'TransferDeadLettered'; Label = 'Transfer DLQ'; Type = 'number'; Sum = $true }
                    @{ Key = 'Messages'; Label = 'All messages'; Type = 'number'; Sum = $true }
                    @{ Key = 'LastAccessed'; Label = 'Last used'; Type = 'datetime'; Console = $true }
                ) }
            @{ Id = 'configuration'; Title = 'Queue and topic configuration'; Section = 'Configuration'; Rows = $readRows; Noun = 'entities'; GroupBy = @('Kind'); ConsoleLimit = 15; NoConsole = $true
                Columns = @(
                    @{ Key = 'Entity'; Label = 'Entity'; Type = 'resource'; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Pdf = $true }
                    @{ Key = 'LockDuration'; Label = 'Lock'; Pdf = $true }
                    @{ Key = 'MaxDeliveryCount'; Label = 'Max deliveries'; Type = 'number'; Pdf = $true }
                    @{ Key = 'DefaultTtl'; Label = 'Default TTL'; Pdf = $true }
                    @{ Key = 'Sessions'; Label = 'Sessions'; Facet = $true; Pdf = $true }
                    @{ Key = 'DuplicateDetection'; Label = 'Duplicate detection'; Facet = $true }
                    @{ Key = 'DuplicateWindow'; Label = 'Duplicate window' }
                    @{ Key = 'DeadLetterOnExpiration'; Label = 'DLQ on expiry'; Facet = $true }
                    @{ Key = 'Ordering'; Label = 'Ordering'; Facet = $true }
                    @{ Key = 'MaxMessageSizeKB'; Label = 'Max message KB'; Type = 'number' }
                    @{ Key = 'Partitioned'; Label = 'Partitioned'; Facet = $true }
                    @{ Key = 'Express'; Label = 'Express'; Facet = $true }
                    @{ Key = 'BatchedOperations'; Label = 'Batched operations'; Facet = $true }
                    @{ Key = 'AutoDeleteOnIdle'; Label = 'Auto-delete on idle' }
                    @{ Key = 'ForwardTo'; Label = 'Forward to'; Pdf = $true }
                    @{ Key = 'ForwardDeadLetteredTo'; Label = 'Forward dead-letters to' }
                    @{ Key = 'Created'; Label = 'Created'; Type = 'datetime' }
                    @{ Key = 'Updated'; Label = 'Updated'; Type = 'datetime' }
                ) }
            @{ Id = 'subscriptionconfiguration'; Title = 'Subscription configuration'; Section = 'Configuration'; Rows = $subscriptionRows; Noun = 'subscriptions'; GroupBy = @('Topic'); NoConsole = $true
                Columns = @(
                    @{ Key = 'Topic'; Label = 'Topic'; Facet = $true; Pdf = $true }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Pdf = $true }
                    @{ Key = 'LockDuration'; Label = 'Lock'; Pdf = $true }
                    @{ Key = 'MaxDeliveryCount'; Label = 'Max deliveries'; Type = 'number'; Pdf = $true }
                    @{ Key = 'DefaultTtl'; Label = 'Default TTL'; Pdf = $true }
                    @{ Key = 'Sessions'; Label = 'Sessions'; Facet = $true }
                    @{ Key = 'AutoDeleteOnIdle'; Label = 'Auto-delete on idle' }
                    @{ Key = 'ForwardTo'; Label = 'Forward to'; Pdf = $true }
                    @{ Key = 'ForwardDeadLetteredTo'; Label = 'Forward dead-letters to' }
                    @{ Key = 'Created'; Label = 'Created'; Type = 'datetime' }
                    @{ Key = 'Updated'; Label = 'Updated'; Type = 'datetime' }
                ) }
            @{ Id = 'metrics'; Title = "Metrics - last $TimeRange"; Section = 'Metrics'; Rows = @($r.Metrics); Noun = 'metrics'; GroupBy = @('Entity', 'Metric'); ConsoleLimit = 30
                Columns = @(
                    @{ Key = 'Entity'; Label = 'Entity'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Metric'; Label = 'Metric'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Total'; Label = 'Total'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Average'; Label = 'Average'; Type = 'number'; Format = 'N2'; Console = $true; Pdf = $true }
                    @{ Key = 'Peak'; Label = 'Peak'; Type = 'number'; Format = 'N0'; Console = $true; Pdf = $true }
                    @{ Key = 'Latest'; Label = 'Latest'; Type = 'number'; Format = 'N0' }
                    @{ Key = 'Trend'; Label = 'Trend'; Console = $unicode }
                ) }
            @{ Id = 'samples'; Title = 'Live samples'; Section = 'Metrics'; Rows = @($r.Samples); Noun = 'samples'; GroupBy = @('Entity'); ConsoleLimit = 30
                Columns = @(
                    @{ Key = 'Time'; Label = 'Time'; Type = 'datetime'; Console = $true; Pdf = $true }
                    @{ Key = 'Entity'; Label = 'Queue or subscription'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Active'; Label = 'Active'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'DeadLettered'; Label = 'Dead-lettered'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Scheduled'; Label = 'Scheduled'; Type = 'number' }
                    @{ Key = 'SizeMB'; Label = 'Size MB'; Type = 'number'; Format = 'N3' }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Signal', 'Finding', 'Severity'); ConsoleLimit = 20
                Empty = 'Nothing to look at.'; EmptyStatus = 'Success'
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Entity'; Label = 'Entity'; Console = $true; Pdf = $true }
                    @{ Key = 'Signal'; Label = 'Signal'; Facet = $true; Console = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'access'; Title = 'What you can see'; Section = 'What you can see'; Rows = @($r.Access); Noun = 'entities'; GroupBy = @('LiveState', 'Metrics'); ConsoleLimit = 20; NoConsole = (-not $stats.NotRead -and $r.MetricStatus -in 'Read', 'Skipped')
                Columns = @(
                    @{ Key = 'Entity'; Label = 'Entity'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'LiveState'; Label = 'Live state'; Type = 'badge'; Tones = @{ Read = 'good'; 'No role' = 'bad'; 'Not found' = 'warn'; Failed = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subscriptions'; Label = 'Subscriptions'; Console = $true }
                    @{ Key = 'Metrics'; Label = 'Metrics'; Type = 'badge'; Tones = @{ Read = 'good'; 'No permission' = 'warn'; Skipped = 'neutral'; 'No data' = 'neutral'; Failed = 'bad' }; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Needed'; Label = 'To see more'; Type = 'wide'; Console = $true; Pdf = $true }
                ) }
        )
        Hint        = '-EntityName takes several names (wildcards with namespace access); -TimeRange 7d looks further back; -Sample 10 reads the live counts ten times for a trend without metrics; -View Subscription, Metric, Sample, Finding or Access returns those rows; -HtmlPath, -PdfPath or -CsvPath for a report.'
    }
    $rows = @(switch ($View) { 'Subscription' { $subscriptionRows } 'Metric' { $r.Metrics } 'Sample' { $r.Samples } 'Finding' { $r.Findings } 'Access' { $r.Access } default { $entityRows } })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
