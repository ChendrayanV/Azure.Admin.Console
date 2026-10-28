function ConvertTo-AACServiceBusLookup {
    <#
    .SYNOPSIS
        Shapes what Show-AACServiceBusEntity read - entities, subscriptions,
        metrics, samples - into rows, findings and what the sign-in could see.
    .DESCRIPTION
        Rows: AAC.ServiceBusLookup (a queue or topic; a topic's message
        counts are the sum of its subscriptions'), AAC.ServiceBusLookupSubscription,
        AAC.ServiceBusLookupMetric (an entity's metric over the time range:
        total, average, peak, latest and a trend), AAC.ServiceBusLookupSample
        (one live read), AAC.ServiceBusLookupFinding and
        AAC.ServiceBusLookupAccess (per entity: what could be read, and the
        role that would show the rest).

        MetricStatus: Read (at least one metric group answered), No
        permission (every group 403), Failed, Skipped (-SkipMetrics) or None
        (nothing to read metrics for).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $NamespaceId,

        # Read-AACMetric's answer for the namespace (call key -> result), or $null.
        [hashtable] $Metric,

        [ValidateSet('Read', 'Skipped')]
        [string] $MetricMode = 'Read',

        [AllowEmptyCollection()]
        [object[]] $Sample = @(),

        [hashtable] $MetricSet = (Get-AACServiceBusEntityMetricSet)
    )

    $namespace = ($NamespaceId.TrimEnd('/') -split '/')[-1]
    $now = [datetime]::UtcNow
    $notices = [System.Collections.Generic.List[string]]::new()
    $prop = { param($Body) if ($Body -is [System.Collections.IDictionary] -and $Body['properties'] -is [System.Collections.IDictionary]) { $Body['properties'] } else { @{} } }
    $count = { param($P, [string] $Key) if ($P['countDetails'] -is [System.Collections.IDictionary] -and $null -ne $P['countDetails'][$Key]) { [long]$P['countDetails'][$Key] } else { [long]0 } }
    $date = {
        param($Value)
        $d = if ($Value -is [datetime]) { $Value.ToUniversalTime() } elseif ($Value) { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal') } else { $null }
        # Azure says 0001-01-01 for "never".
        if ($d -and $d.Year -gt 1970) { $d } else { $null }
    }
    $span = {
        param($Value)
        if (-not $Value) { return '' }
        try { $t = [System.Xml.XmlConvert]::ToTimeSpan([string]$Value) } catch { return [string]$Value }
        if ($t.TotalDays -ge 3650) { return 'never' }
        $parts = @(if ($t.Days) { "$($t.Days)d" }; if ($t.Hours) { "$($t.Hours)h" }; if ($t.Minutes) { "$($t.Minutes)m" }; if ($t.Seconds -or $t.Milliseconds) { "$([Math]::Round($t.Seconds + $t.Milliseconds / 1000, 1))s" })
        if ($parts.Count) { $parts -join ' ' } else { '0s' }
    }
    $yes = { param($Value) if ($null -eq $Value) { $null } else { [bool]$Value } }
    $idle = { param($Accessed) if ($Accessed) { [int][Math]::Floor(($now - $Accessed).TotalDays) } else { $null } }

    # --- Metrics: by entity (lower case) and metric --------------------------------------------------------------
    $series = @{}
    $answered = 0; $denied = 0; $calls = 0
    if ($Metric) {
        foreach ($key in @($Metric.Keys | Sort-Object)) {
            $calls++
            $result = $Metric[$key]
            if ($result.Error) {
                if ([int]$result['Status'] -eq 403) { $denied++ }
                elseif ($key -notlike 'Premium*') { $notices.Add("The $(($key -split '#')[0].ToLowerInvariant()) metrics couldn't be read: $($result.Error -replace '\s+', ' ')") }
                continue
            }
            $answered++
            foreach ($s in @($result.Series)) {
                $entity = if ($s.Dims.Contains('entityname')) { ([string]$s.Dims['entityname']).ToLowerInvariant() } else { '' }
                $k = "$entity|$($s.Name)"
                if (-not $series.Contains($k)) { $series[$k] = [System.Collections.Generic.List[object]]::new() }
                foreach ($p in @($s.Points)) { $series[$k].Add($p) }
            }
        }
    }
    $metricStatus = if ($MetricMode -eq 'Skipped') { 'Skipped' } elseif (-not $calls) { 'None' } elseif ($answered) { 'Read' } elseif ($denied) { 'No permission' } else { 'Failed' }
    $value = { param($Point, [string] $Name) if ($Point -is [System.Collections.IDictionary] -and $null -ne $Point[$Name]) { [double]$Point[$Name] } else { $null } }
    $summary = {
        param([string] $Entity, [string] $Name)
        $points = @(if ($series.Contains("$($Entity.ToLowerInvariant())|$Name")) { $series["$($Entity.ToLowerInvariant())|$Name"] | Sort-Object -Property { [string]$_['timeStamp'] } })
        if (-not $points.Count) { return $null }
        $kind = $MetricSet.Kind[$Name]
        if ($kind -eq 'Total') {
            $values = @($points | ForEach-Object { $v = & $value $_ 'total'; if ($null -eq $v) { 0 } else { $v } })
            return @{ Total = [double]($values | Measure-Object -Sum).Sum; Average = $null; Peak = [double]($values | Measure-Object -Maximum).Maximum; Latest = $values[-1]; Trend = $values }
        }
        $averages = @($points | ForEach-Object { & $value $_ 'average' } | Where-Object { $null -ne $_ })
        $peaks = @($points | ForEach-Object { & $value $_ 'maximum' } | Where-Object { $null -ne $_ })
        @{ Total = $null
            Average = $(if ($averages.Count) { [Math]::Round(($averages | Measure-Object -Average).Average, 2) } else { $null })
            Peak = $(if ($peaks.Count) { [double]($peaks | Measure-Object -Maximum).Maximum } elseif ($averages.Count) { [double]($averages | Measure-Object -Maximum).Maximum } else { $null })
            Latest = $(if ($averages.Count) { $averages[-1] } elseif ($peaks.Count) { $peaks[-1] } else { $null }); Trend = $(if ($averages.Count) { $averages } else { $peaks }) }
    }

    # --- Entities and subscriptions --------------------------------------------------------------------------------
    $entityRows = [System.Collections.Generic.List[object]]::new()
    $subscriptionRows = [System.Collections.Generic.List[object]]::new()
    $metricRows = [System.Collections.Generic.List[object]]::new()
    $accessRows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Entity, [string] $Signal, [string] $Title, [string] $Detail, [string] $Recommendation)
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBusLookupFinding'; Severity = $Severity; Namespace = $namespace; Entity = $Entity; Signal = $Signal; Finding = $Title; Detail = $Detail; Recommendation = $Recommendation })
    }
    $outcomeText = @{ Read = 'Read'; NoRole = 'No role'; NotFound = 'Not found'; Failed = 'Failed' }

    foreach ($e in $State.Entities) {
        $read = $e.Outcome -eq 'Read'
        $p = & $prop $e.Body
        $subs = @(if ($e.Subscriptions) { $e.Subscriptions.Items })
        $subsRead = $e.Subscriptions -and $e.Subscriptions.Outcome -eq 'Read'
        foreach ($s in $subs) {
            $sp = & $prop $s
            $accessed = & $date $sp['accessedAt']
            $subscriptionRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.ServiceBusLookupSubscription'; Namespace = $namespace; Topic = $e.Name; Subscription = [string]$s['name']; Status = [string]$sp['status']
                    Active = & $count $sp 'activeMessageCount'; DeadLettered = & $count $sp 'deadLetterMessageCount'; Scheduled = & $count $sp 'scheduledMessageCount'
                    Transfer = & $count $sp 'transferMessageCount'; TransferDeadLettered = & $count $sp 'transferDeadLetterMessageCount'; Messages = [long]$sp['messageCount']
                    MaxDeliveryCount = $sp['maxDeliveryCount']; LockDuration = & $span $sp['lockDuration']; DefaultTtl = & $span $sp['defaultMessageTimeToLive']; Sessions = & $yes $sp['requiresSession']
                    DeadLetterOnExpiration = & $yes $sp['deadLetteringOnMessageExpiration']; DeadLetterOnFilterError = & $yes $sp['deadLetteringOnFilterEvaluationExceptions']
                    AutoDeleteOnIdle = & $span $sp['autoDeleteOnIdle']; ForwardTo = [string]$sp['forwardTo']; ForwardDeadLetteredTo = [string]$sp['forwardDeadLetteredMessagesTo']
                    Created = & $date $sp['createdAt']; Updated = & $date $sp['updatedAt']; LastAccessed = $accessed; IdleDays = & $idle $accessed; ResourceId = [string]$s['id']
                })
        }
        $mine = @($subscriptionRows | Where-Object Topic -EQ $e.Name)
        $isTopic = $e.Kind -eq 'Topic'
        # A topic keeps its messages in its subscriptions: its counts are theirs, added up.
        $sum = { param([string] $Column, [string] $Key) if ($isTopic) { [long](@($mine | ForEach-Object $Column) | Measure-Object -Sum).Sum } else { & $count $p $Key } }
        $sizeBytes = if ($null -ne $p['sizeInBytes']) { [double]$p['sizeInBytes'] } else { $null }
        $maxMb = if ($null -ne $p['maxSizeInMegabytes']) { [double]$p['maxSizeInMegabytes'] } else { $null }
        $accessed = & $date $p['accessedAt']
        $m = @{}
        if ($read) { foreach ($name in @($MetricSet.Label.Keys)) { $sm = & $summary $e.Name $name; if ($sm) { $m[$name] = $sm } } }
        $total = { param([string] $Name) if ($m.Contains($Name)) { $m[$Name].Total } else { $null } }
        $peak = { param([string] $Name) if ($m.Contains($Name)) { $m[$Name].Peak } else { $null } }
        $samples = @($Sample | Where-Object { $_.Entity -eq $e.Name -or ($isTopic -and $_.Entity -like "$($e.Name)/*") })
        $sampleTrend = ''; $change = $null; $perMinute = $null
        if ($samples.Count) {
            $byTime = @($samples | Group-Object -Property { $_.Time.Ticks } | Sort-Object -Property { [long]$_.Name } | ForEach-Object { @{ Time = [datetime]::new([long]$_.Name, 'Utc'); Active = [long](@($_.Group | ForEach-Object { $_.Active }) | Measure-Object -Sum).Sum } })
            $sampleTrend = ConvertTo-AACSparkline -Value @($byTime | ForEach-Object { $_.Active })
            if ($byTime.Count -gt 1) {
                $change = $byTime[-1].Active - $byTime[0].Active
                $minutes = ($byTime[-1].Time - $byTime[0].Time).TotalMinutes
                $perMinute = if ($minutes -gt 0) { [Math]::Round($change / $minutes, 1) } else { $null }
            }
        }
        $row = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.ServiceBusLookup'; Namespace = $namespace; Entity = $e.Name; Kind = $e.Kind; Status = $(if ($read) { [string]$p['status'] } else { $outcomeText[$e.Outcome] })
            Access = $(if ($read) { $State.Access } else { 'None' }); Metrics = $(if (-not $read) { '' } elseif ($metricStatus -eq 'Read' -and -not $m.Count) { 'No data' } else { $metricStatus })
            Active = $(if ($read) { & $sum 'Active' 'activeMessageCount' } else { $null }); DeadLettered = $(if ($read) { & $sum 'DeadLettered' 'deadLetterMessageCount' } else { $null })
            Scheduled = $(if ($read) { & $count $p 'scheduledMessageCount' } else { $null }); Transfer = $(if ($read) { & $sum 'Transfer' 'transferMessageCount' } else { $null })
            TransferDeadLettered = $(if ($read) { & $sum 'TransferDeadLettered' 'transferDeadLetterMessageCount' } else { $null })
            Messages = $(if (-not $read) { $null } elseif ($isTopic) { [long](@($mine | ForEach-Object Messages) | Measure-Object -Sum).Sum } else { [long]$p['messageCount'] })
            Subscriptions = $(if ($isTopic -and $read) { $p['subscriptionCount'] } else { $null })
            SizeMB = $(if ($null -ne $sizeBytes) { [Math]::Round($sizeBytes / 1MB, 2) } else { $null }); MaxSizeMB = $maxMb
            UsedPct = $(if ($null -ne $sizeBytes -and $maxMb) { [Math]::Round($sizeBytes / ($maxMb * 1MB) * 100, 1) } else { $null })
            Incoming = & $total 'IncomingMessages'; Outgoing = & $total 'OutgoingMessages'; Completed = & $total 'CompleteMessage'; Abandoned = & $total 'AbandonMessage'
            Requests = & $total 'IncomingRequests'; ServerErrors = & $total 'ServerErrors'; UserErrors = & $total 'UserErrors'; Throttled = & $total 'ThrottledRequests'
            PeakActive = & $peak 'ActiveMessages'; PeakDeadLettered = & $peak 'DeadletteredMessages'
            AvgSendLatencyMs = $(if ($m.Contains('ServerSendLatency')) { $m['ServerSendLatency'].Average } else { $null })
            IncomingTrend = $(if ($m.Contains('IncomingMessages')) { ConvertTo-AACSparkline -Value $m['IncomingMessages'].Trend } else { '' })
            ActiveTrend = $(if ($m.Contains('ActiveMessages')) { ConvertTo-AACSparkline -Value $m['ActiveMessages'].Trend } else { $sampleTrend })
            SampledChange = $change; SampledPerMinute = $perMinute
            MaxDeliveryCount = $p['maxDeliveryCount']; LockDuration = & $span $p['lockDuration']; DefaultTtl = & $span $p['defaultMessageTimeToLive']; Sessions = & $yes $p['requiresSession']
            DuplicateDetection = & $yes $p['requiresDuplicateDetection']; DuplicateWindow = & $span $p['duplicateDetectionHistoryTimeWindow']; DeadLetterOnExpiration = & $yes $p['deadLetteringOnMessageExpiration']
            Ordering = & $yes $p['supportOrdering']; MaxMessageSizeKB = $p['maxMessageSizeInKilobytes']; Partitioned = & $yes $p['enablePartitioning']; Express = & $yes $p['enableExpress']
            BatchedOperations = & $yes $p['enableBatchedOperations']; AutoDeleteOnIdle = & $span $p['autoDeleteOnIdle']; ForwardTo = [string]$p['forwardTo']; ForwardDeadLetteredTo = [string]$p['forwardDeadLetteredMessagesTo']
            Created = & $date $p['createdAt']; Updated = & $date $p['updatedAt']; LastAccessed = $accessed; IdleDays = & $idle $accessed
            Error = [string]$e.Error; ResourceId = $(if ($read -and $e.Body['id']) { [string]$e.Body['id'] } else { '' })
        }
        $entityRows.Add($row)

        foreach ($name in @($MetricSet.Label.Keys | Where-Object { $m.Contains($_) })) {
            $sm = $m[$name]
            $metricRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.ServiceBusLookupMetric'; Namespace = $namespace; Entity = $e.Name; Metric = $MetricSet.Label[$name]; MetricName = $name
                    Total = $sm.Total; Average = $sm.Average; Peak = $sm.Peak; Latest = $sm.Latest; Trend = ConvertTo-AACSparkline -Value $sm.Trend; Points = @($sm.Trend).Count
                })
        }

        $accessRows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.ServiceBusLookupAccess'; Entity = $e.Name; Kind = $(if ($e.Kind) { $e.Kind } else { '?' }); LiveState = $outcomeText[$e.Outcome]
                Subscriptions = $(if (-not $isTopic -or -not $read) { '' } elseif ($subsRead) { "Read ($($subs.Count))" } else { $outcomeText[$e.Subscriptions.Outcome] })
                Metrics = $(if (-not $read) { '' } else { $row.Metrics })
                Needed = $(if ($e.Outcome -eq 'NoRole') { 'Azure Service Bus Data Receiver (or Sender, or Owner) on this entity' } elseif ($e.Outcome -eq 'NotFound') { 'Check the name and -EntityKind' } elseif ($read -and $metricStatus -eq 'No permission') { 'For metrics: Monitoring Reader (or Reader) on the namespace' } else { '' })
            })

        # --- Findings ----------------------------------------------------------------------------------------------
        $label = if ($e.Kind) { "$($e.Kind.ToLowerInvariant()) $($e.Name)" } else { $e.Name }
        if ($e.Outcome -eq 'NoRole') { & $finding 'Medium' $e.Name 'Access' 'No role on the entity' $e.Error 'Ask the namespace owner for Azure Service Bus Data Receiver (or Sender) on this queue or topic.'; continue }
        if ($e.Outcome -eq 'NotFound') { & $finding 'Medium' $e.Name 'Access' 'Entity not found' $e.Error 'Check the spelling (names are exact) and -EntityKind.'; continue }
        if (-not $read) { & $finding 'Medium' $e.Name 'Access' 'Entity could not be read' $e.Error 'Try again; if it persists, check the network can reach Azure Resource Manager.'; continue }
        if ($row.Status -eq 'Disabled') { & $finding 'High' $e.Name 'Health' 'Entity disabled' "The $label is Disabled: nothing can be sent or received." 'Set the status back to Active once the reason is understood.' }
        elseif ($row.Status -in 'SendDisabled', 'ReceiveDisabled') { & $finding 'Medium' $e.Name 'Health' "Entity $($row.Status)" "The $label is $($row.Status)." 'Set the status back to Active when the change is no longer needed.' }
        if ($row.DeadLettered) { & $finding 'High' $e.Name 'Messages' 'Dead-lettered messages' ('{0:N0} message(s) in the dead-letter queue{1}.' -f $row.DeadLettered, $(if ($isTopic) { ' of its subscriptions' } else { '' })) 'Find out why (the DeadLetterReason property), fix the cause, then resubmit or purge the dead-letter queue.' }
        if ($row.TransferDeadLettered) { & $finding 'High' $e.Name 'Messages' 'Transfer dead-lettered messages' ('{0:N0} message(s) could not be auto-forwarded.' -f $row.TransferDeadLettered) 'Check the forwarding target exists and accepts messages, then process the transfer dead-letter queue.' }
        if ($null -ne $row.UsedPct -and $row.UsedPct -ge 80) { & $finding 'High' $e.Name 'Capacity' 'Entity filling up' ('{0:N1}% of {1:N0} MB used: sends fail at 100%.' -f $row.UsedPct, $row.MaxSizeMB) 'Drain the backlog, or raise the maximum size.' }
        if ($row.Throttled) { & $finding 'Medium' $e.Name 'Health' 'Requests throttled' ('{0:N0} throttled request(s) in the time range.' -f $row.Throttled) 'Spread the load, batch operations, or add messaging units (Premium).' }
        if ($row.ServerErrors) { & $finding 'Medium' $e.Name 'Health' 'Server errors' ('{0:N0} server error(s) in the time range.' -f $row.ServerErrors) 'Make sure clients retry; check Azure Service Health for the region.' }
        if ($null -ne $row.Incoming -and $row.Incoming -gt 0 -and -not $row.Outgoing -and $row.Active) { & $finding 'Medium' $e.Name 'Messages' 'Messages arriving, none received' ('{0:N0} message(s) in, none out, {1:N0} waiting.' -f $row.Incoming, $row.Active) 'Check the receivers are running and can connect.' }
        $growing = $false; $how = ''
        if ($m.Contains('ActiveMessages')) {
            $levels = @($m['ActiveMessages'].Trend)
            if ($levels.Count -ge 3 -and $levels[-1] -ge 100 -and $levels[-1] -gt 1.5 * [Math]::Max(1, $levels[0])) { $growing = $true; $how = ('from {0:N0} to {1:N0} active over the time range' -f $levels[0], $levels[-1]) }
        }
        elseif ($null -ne $change -and $change -gt 0 -and $null -ne $perMinute -and $perMinute -gt 0) { $growing = $true; $how = ('{0:N0} more active over the samples ({1:N1} a minute)' -f $change, $perMinute) }
        if ($growing) { & $finding 'Medium' $e.Name 'Messages' 'Backlog growing' "Active messages grew: $how." 'Check the receivers keep up: scale them out, or look for slow or failing message handling.' }
        if ($null -ne $row.IdleDays -and $row.IdleDays -ge 30) { & $finding 'Low' $e.Name 'Configuration' 'Not used for 30 days' "The $label was last used $($row.IdleDays) days ago." 'Delete it if nothing uses it any more.' }
        if (-not $isTopic -and $row.DefaultTtl -and $row.DefaultTtl -ne 'never' -and $row.DeadLetterOnExpiration -eq $false) { & $finding 'Low' $e.Name 'Configuration' 'Expired messages are dropped' "Messages expire after $($row.DefaultTtl) and are deleted, not dead-lettered." 'Turn on dead-lettering on expiration if expired messages matter.' }
        foreach ($s in $mine) {
            if ($s.DeadLettered) { & $finding 'High' "$($e.Name)/$($s.Subscription)" 'Messages' 'Dead-lettered messages' ('{0:N0} message(s) in the subscription''s dead-letter queue.' -f $s.DeadLettered) 'Find out why (the DeadLetterReason property), fix the cause, then resubmit or purge the dead-letter queue.' }
            if ($s.Status -eq 'Disabled') { & $finding 'High' "$($e.Name)/$($s.Subscription)" 'Health' 'Subscription disabled' 'Messages to this subscription are not delivered.' 'Set the status back to Active once the reason is understood.' }
        }
        if ($isTopic -and $e.Subscriptions -and $e.Subscriptions.Outcome -ne 'Read') { $notices.Add("The subscriptions of topic $($e.Name) couldn't be read: $($e.Subscriptions.Error)") }
    }
    # Premium CPU and memory belong to the namespace, not an entity.
    foreach ($name in 'NamespaceCpuUsage', 'NamespaceMemoryUsage') {
        $sm = & $summary '' $name
        if ($sm) { $metricRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBusLookupMetric'; Namespace = $namespace; Entity = '(namespace)'; Metric = $MetricSet.Label[$name]; MetricName = $name; Total = $null; Average = $null; Peak = $sm.Peak; Latest = $sm.Latest; Trend = ConvertTo-AACSparkline -Value $sm.Trend; Points = @($sm.Trend).Count }) }
    }
    if ($metricStatus -eq 'No permission') { $notices.Add('Metrics need read access on the namespace (Monitoring Reader or Reader there): an entity role shows the live state only. -Sample reads the live counts a few times for a short trend.') }

    $rank = @{ High = 0; Medium = 1; Low = 2 }
    $read = @($entityRows | Where-Object Access -NE 'None')
    @{
        Entities      = $entityRows.ToArray()
        Subscriptions = $subscriptionRows.ToArray()
        Metrics       = $metricRows.ToArray()
        Samples       = @($Sample | Sort-Object -Property { $_.Time }, { $_.Entity } | ForEach-Object { [pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBusLookupSample'; Namespace = $namespace; Time = $_.Time; Entity = $_.Entity; Kind = $_.Kind; Active = $_.Active; DeadLettered = $_.DeadLettered; Scheduled = $_.Scheduled; SizeMB = $_.SizeMB } })
        Findings      = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Entity)
        Access        = $accessRows.ToArray()
        MetricStatus  = $metricStatus
        Notices       = $notices.ToArray()
        Stats         = @{
            Entities = $entityRows.Count; Read = $read.Count; NotRead = $entityRows.Count - $read.Count
            Active = [long](@($read | ForEach-Object Active) | Measure-Object -Sum).Sum; DeadLettered = [long](@($read | ForEach-Object { $_.DeadLettered + $_.TransferDeadLettered }) | Measure-Object -Sum).Sum
            Scheduled = [long](@($read | ForEach-Object Scheduled) | Measure-Object -Sum).Sum; Throttled = [long](@($read | ForEach-Object { [long]$_.Throttled }) | Measure-Object -Sum).Sum
            High = @($findings | Where-Object Severity -EQ 'High').Count
        }
    }
}
