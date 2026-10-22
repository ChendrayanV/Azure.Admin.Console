function ConvertTo-AACServiceBusAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACServiceBusAssessment read into per-namespace
        health, capacity, messages, posture and resilience, per-entity
        message counts, findings and a heat map.
    .DESCRIPTION
        No Azure calls. Per namespace (AAC.ServiceBusAssessment):
          health      over the period: IncomingRequests, SuccessfulRequests,
                      ServerErrors, UserErrors, ThrottledRequests,
                      IncomingMessages, OutgoingMessages, ErrorRate
          capacity    Premium: CpuMax and MemoryMax (% of the messaging
                      units)
          messages    the entities' counts now: Queues, Topics,
                      Subscriptions, ActiveMessages, DeadLetters, Scheduled,
                      SizeMB, FullestPct
          posture     Tier, MessagingUnits, MinTls, LocalAuth (SAS keys
                      allowed), Network (Private, Firewall, Public),
                      PrivateEndpoints, Encryption, Identity, ManageKeys
                      (namespace-wide SAS rules with Manage rights), LogsTo
          resilience  ZoneRedundant, GeoDr (an alias, or geo-replication)
        Per queue, topic and subscription (AAC.ServiceBusEntity): status,
        active, dead-lettered, transfer dead-lettered and scheduled
        messages, size against its maximum, delivery and lock settings,
        when it was last used.
        Findings (AAC.ServiceBusFinding: Severity, Namespace, Entity,
        Signal, Finding, Detail, Recommendation) - Signal is the heat map's
        column: Health, Capacity, Messages, Security, Resilience, Cost.
        Returns @{ Namespaces; Entities; Findings; HeatMap; Messages; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Namespace,

        # Read-AACServiceBusEntity's result, by namespace ID.
        [hashtable] $Entity = @{},

        # Read-AACMetric's result (Core, Premium), by namespace ID.
        [hashtable] $Metric = @{},

        # Workspace resource ID (lower case) -> name.
        [hashtable] $WorkspaceName = @{},

        [hashtable] $SubscriptionName = @{},

        [datetime] $Now = [datetime]::UtcNow
    )

    $at = { param($Row, [string[]] $Keys) Get-AACMember -InputObject $Row -Key $Keys }
    $sum = { param([object[]] $Points, [string] $Field) $t = 0.0; foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { $t += [double]$v } }; $t }
    $peak = { param([object[]] $Points, [string] $Field) $m = $null; foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v -and ($null -eq $m -or [double]$v -gt $m)) { $m = [double]$v } }; $m }
    # Measure-Object returns nothing for no input (and .Sum then fails under StrictMode): this returns 0.
    $sumOf = { param([object[]] $Rows, [string] $Property) $t = 0.0; foreach ($row in $Rows) { if ($null -ne $row.$Property) { $t += [double]$row.$Property } }; $t }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $call = { param([string] $Id, [string] $Key) if ($Metric.Contains($Id) -and $Metric[$Id].Contains($Key)) { $Metric[$Id][$Key] } else { $null } }
    $pointsOf = { param($Answer, [string] $Name) @(if ($Answer -and -not $Answer.Error) { foreach ($s in $Answer.Series) { if ($s.Name -eq $Name) { $s.Points } } }) }
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    $readOk = { param($Answer) [bool]($Answer -and -not $Answer['Error']) }
    # accessedAt: never used reads 0001-01-01; ConvertFrom-Json may already have made it a DateTime.
    $when = {
        param($Value)
        $d = if ($Value -is [datetime]) { $Value } elseif ($Value) { try { [datetime]::Parse([string]$Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) } catch { $null } } else { $null }
        if ($d -and $d.Year -gt 2000) { $d.ToUniversalTime() } else { $null }
    }
    # An ISO 8601 duration; the maximum (P10675199D...) means messages never expire.
    $expires = { param($Ttl) $t = [string]$Ttl; if (-not $t -or $t -like 'P10675199D*') { return $false }; try { $null = [System.Xml.XmlConvert]::ToTimeSpan($t); $true } catch { $false } }

    $findings = [System.Collections.Generic.List[object]]::new()
    $namespaceRows = [System.Collections.Generic.List[object]]::new()
    $entityRows = [System.Collections.Generic.List[object]]::new()
    $heatRows = [System.Collections.Generic.List[object]]::new()
    $signals = @('Health', 'Capacity', 'Messages', 'Security', 'Resilience', 'Cost')
    $messageTotals = [ordered]@{ Active = 0.0; 'Dead-lettered' = 0.0; Scheduled = 0.0; 'Transfer dead-lettered' = 0.0 }

    foreach ($n in @($Namespace | Sort-Object -Property { [string]$_['name'] })) {
        $id = [string]$n['id']
        $name = [string]$n['name']
        $p = $n['properties']
        $tier = [string]$n['tier']
        $premium = $tier -eq 'Premium'
        $read = if ($Entity.Contains($id)) { $Entity[$id] } else { @{ Queues = $null; Topics = $null; Network = $null; Rules = $null; GeoDr = $null; Logs = $null; Subscriptions = @{} } }
        $find = {
            param([string] $Severity, [string] $Signal, [string] $Title, [string] $Detail, [string] $Fix, [string] $EntityName = '')
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBusFinding'; Severity = $Severity; Namespace = $name; Entity = $EntityName; Signal = $Signal; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceGroup = [string]$n['resourceGroup']; Subscription = & $subName ([string]$n['subscriptionId']); ResourceId = $id })
        }

        # --- Health and capacity: Azure Monitor over the period -------------------------------------------------------
        $core = & $call $id 'Core'
        $metricsRead = [bool]($core -and -not $core.Error)
        $requests = [long](& $sum (& $pointsOf $core 'IncomingRequests') 'total')
        $successful = [long](& $sum (& $pointsOf $core 'SuccessfulRequests') 'total')
        $serverErrors = [long](& $sum (& $pointsOf $core 'ServerErrors') 'total')
        $userErrors = [long](& $sum (& $pointsOf $core 'UserErrors') 'total')
        $throttled = [long](& $sum (& $pointsOf $core 'ThrottledRequests') 'total')
        $incoming = [long](& $sum (& $pointsOf $core 'IncomingMessages') 'total')
        $outgoing = [long](& $sum (& $pointsOf $core 'OutgoingMessages') 'total')
        $rateOf = { param([double] $Count) if ($requests) { 100.0 * $Count / $requests } else { 0 } }
        $premiumMetrics = & $call $id 'Premium'
        $cpu = & $round (& $peak (& $pointsOf $premiumMetrics 'NamespaceCpuUsage') 'maximum')
        $memory = & $round (& $peak (& $pointsOf $premiumMetrics 'NamespaceMemoryUsage') 'maximum')

        # --- Entities: queues, topics and subscriptions, as they are now ----------------------------------------------
        $mine = [System.Collections.Generic.List[object]]::new()
        $addEntity = {
            param([string] $Kind, [string] $EntityName, $Properties, [int] $SubscriptionCount = -1)
            $counts = & $at $Properties 'countDetails'
            $active = [long](& $at $counts 'activeMessageCount')
            $dead = [long](& $at $counts 'deadLetterMessageCount')
            $transfer = [long](& $at $counts 'transferDeadLetterMessageCount')
            $scheduled = [long](& $at $counts 'scheduledMessageCount')
            $sizeMb = if ($null -ne (& $at $Properties 'sizeInBytes')) { & $round ([double](& $at $Properties 'sizeInBytes') / 1MB) 2 } else { $null }
            $maxMb = & $at $Properties 'maxSizeInMegabytes'
            $usedPct = if ($null -ne $sizeMb -and $maxMb) { & $round (100.0 * $sizeMb / [double]$maxMb) 1 } else { $null }
            $lastUsed = & $when (& $at $Properties 'accessedAt')
            $idle = if ($lastUsed) { [int][Math]::Floor(($Now - $lastUsed).TotalDays) } else { $null }
            $status = [string](& $at $Properties 'status')
            $row = [pscustomobject][ordered]@{
                PSTypeName             = 'AAC.ServiceBusEntity'
                Namespace              = $name
                Entity                 = $EntityName
                Type                   = $Kind
                Status                 = $status
                ActiveMessages         = $active
                DeadLetters            = $dead
                TransferDeadLetters    = $transfer
                Scheduled              = $scheduled
                SizeMB                 = $sizeMb
                MaxSizeMB              = $maxMb
                UsedPct                = $usedPct
                Subscriptions          = $(if ($SubscriptionCount -ge 0) { $SubscriptionCount } else { $null })
                MaxDeliveryCount       = & $at $Properties 'maxDeliveryCount'
                LockDuration           = [string](& $at $Properties 'lockDuration')
                Sessions               = [string](& $at $Properties 'requiresSession') -eq 'True'
                DuplicateDetection     = [string](& $at $Properties 'requiresDuplicateDetection') -eq 'True'
                DeadLetterOnExpiration = [string](& $at $Properties 'deadLetteringOnMessageExpiration') -eq 'True'
                MessagesExpire         = & $expires (& $at $Properties 'defaultMessageTimeToLive')
                ForwardTo              = [string](& $at $Properties 'forwardTo')
                LastUsed               = $lastUsed
                IdleDays               = $idle
                Findings               = 0
                ResourceGroup          = [string]$n['resourceGroup']
                Subscription           = & $subName ([string]$n['subscriptionId'])
            }
            $mine.Add($row)
            $before = $findings.Count
            $what = "$Kind '$EntityName'"
            if ($dead -gt 0) { & $find $(if ($dead -ge 1000) { 'High' } else { 'Medium' }) 'Messages' 'Dead-lettered messages' ('{0} holds {1:N0} dead-lettered message(s): messages that failed {2} delivery attempts, expired, or broke a filter.' -f $what, $dead, $(if ($null -ne $row.MaxDeliveryCount) { $row.MaxDeliveryCount } else { 'the maximum' })) 'Read the dead-letter queue (DeadLetterReason, DeadLetterErrorDescription), fix the cause - often a poison message or a failing handler - then resubmit or purge; alert on DeadletteredMessages.' $EntityName }
            if ($transfer -gt 0) { & $find 'Medium' 'Messages' 'Transfer dead-lettered messages' ('{0} has {1:N0} message(s) that couldn''t be forwarded (auto-forward or send-via).' -f $what, $transfer) 'Check the forwarding target exists, is active and isn''t full; then resubmit from the transfer dead-letter queue.' $EntityName }
            if ($null -ne $usedPct -and $usedPct -ge 50) { & $find $(if ($usedPct -ge 80) { 'High' } else { 'Medium' }) 'Messages' 'Entity filling up' ('{0} is at {1}% of its {2:N0} MB maximum: at 100% sends fail (QuotaExceeded).' -f $what, $usedPct, [double]$maxMb) 'Drain the backlog (more or faster receivers), raise the maximum size, or partition the entity; alert on Size.' $EntityName }
            if ($status -and $status -ne 'Active') { & $find 'Medium' 'Messages' 'Entity not active' "$what is $status." 'Re-enable it when it should send and receive again - or delete it if it is no longer used.' $EntityName }
            if ($Kind -ne 'Topic' -and $active -ge 10000) { & $find 'Medium' 'Messages' 'Backlog of active messages' ('{0} has {1:N0} active message(s) waiting.' -f $what, $active) 'Check the receivers are running and keeping up: scale them out, use prefetch and concurrent processing, or batch receives.' $EntityName }
            if ($SubscriptionCount -eq 0) { & $find 'Medium' 'Messages' 'Topic with no subscriptions' "$what has no subscription: every message sent to it is dropped." 'Add the subscriptions it needs, or delete the topic.' $EntityName }
            if ($Kind -ne 'Topic' -and -not $row.DeadLetterOnExpiration -and $row.MessagesExpire) { & $find 'Low' 'Messages' 'Expired messages are dropped' "$what lets messages expire, without dead-lettering them." 'Turn on dead-lettering on message expiration, so expired messages can be inspected instead of lost.' $EntityName }
            if ($active -eq 0 -and $dead -eq 0 -and ($null -eq $idle -or $idle -ge 30)) { & $find 'Low' 'Cost' 'Not used for 30 days or more' "$what $(if ($null -eq $idle) { 'has never been used' } else { "was last used $idle days ago" }), and is empty." 'Delete it if nothing uses it any more - unused entities clutter the namespace and its quotas.' $EntityName }
            $row.Findings = $findings.Count - $before
        }
        foreach ($q in (& $itemsOf $read.Queues)) { & $addEntity 'Queue' ([string]$q['name']) $q['properties'] }
        foreach ($t in (& $itemsOf $read.Topics)) {
            $topicId = ([string]$t['id']).ToLowerInvariant()
            $subs = if ($read.Subscriptions.Contains($topicId)) { $read.Subscriptions[$topicId] } else { $null }
            $count = if (& $readOk $subs) { @(& $itemsOf $subs).Count } else { [int](& $at $t 'properties', 'subscriptionCount') }
            & $addEntity 'Topic' ([string]$t['name']) $t['properties'] $count
            foreach ($s in (& $itemsOf $subs)) { & $addEntity 'Subscription' "$([string]$t['name'])/$([string]$s['name'])" $s['properties'] }
        }
        $entityRows.AddRange([object[]]$mine.ToArray())
        $queued = @($mine | Where-Object { $_.Type -ne 'Topic' })
        $active = [long](& $sumOf $queued 'ActiveMessages')
        $dead = [long](& $sumOf $queued 'DeadLetters')
        $scheduledTotal = [long](& $sumOf $queued 'Scheduled')
        $transferTotal = [long](& $sumOf $queued 'TransferDeadLetters')
        $messageTotals['Active'] += $active; $messageTotals['Dead-lettered'] += $dead; $messageTotals['Scheduled'] += $scheduledTotal; $messageTotals['Transfer dead-lettered'] += $transferTotal
        $fullest = @($mine | Where-Object { $null -ne $_.UsedPct } | ForEach-Object { $_.UsedPct } | Sort-Object -Descending | Select-Object -First 1)
        $entitiesRead = (& $readOk $read.Queues) -or (& $readOk $read.Topics)

        # --- Posture ------------------------------------------------------------------------------------------------
        $tls = [string](& $at $p 'minimumTlsVersion')
        $localAuth = [string](& $at $p 'disableLocalAuth') -ne 'True'
        $rules = if (& $readOk $read.Network) { & $at $read.Network 'Body', 'properties' } else { $null }
        $network = if ([string](& $at $p 'publicNetworkAccess') -eq 'Disabled' -or [string](& $at $rules 'publicNetworkAccess') -eq 'Disabled') { 'Private' }
        elseif ([string](& $at $rules 'defaultAction') -eq 'Deny' -or @(& $at $rules 'ipRules').Count -or @(& $at $rules 'virtualNetworkRules').Count) { 'Firewall' }
        else { 'Public' }
        $endpoints = @(@(& $at $p 'privateEndpointConnections') | Where-Object { $_ -and [string](& $at $_ 'properties', 'privateLinkServiceConnectionState', 'status') -eq 'Approved' }).Count
        $cmk = [string](& $at $p 'encryption', 'keySource') -eq 'Microsoft.KeyVault'
        $identity = [string](& $at $n 'identity', 'type')
        $manageKeys = @(& $itemsOf $read.Rules | Where-Object { @(& $at $_ 'properties', 'rights') -contains 'Manage' }).Count
        $logsTo = $null
        foreach ($diagnostic in (& $itemsOf $read.Logs)) {
            $dp = & $at $diagnostic 'properties'
            $workspace = ([string](& $at $dp 'workspaceId')).ToLowerInvariant()
            if (-not $workspace) { continue }
            $on = @(@(& $at $dp 'logs') | Where-Object { $_ -and (& $at $_ 'enabled') -eq $true -and ([string](& $at $_ 'category') -in 'OperationalLogs', 'RuntimeAuditLogs', 'VNetAndIPFilteringLogs' -or [string](& $at $_ 'categoryGroup') -in 'audit', 'allLogs') }).Count
            if ($on) { $logsTo = $workspace; break }
        }
        $logsRead = & $readOk $read.Logs
        $zoneRedundant = [string](& $at $p 'zoneRedundant') -eq 'True'
        $alias = @(& $itemsOf $read.GeoDr).Count -gt 0
        $replicas = @(& $at $p 'geoDataReplication', 'locations').Count -gt 1
        $geoDr = $alias -or $replicas
        $units = [int]$n['capacity']

        # --- Findings: namespace ------------------------------------------------------------------------------------
        if ($throttled -gt 0) {
            $r = & $rateOf $throttled
            $fix = if ($premium) { 'Add messaging units - or scale them automatically on CPU usage - and spread the load over more entities or partitions.' } else { 'Standard namespaces share capacity and are throttled when the credits run out: retry with backoff, and move busy workloads to Premium.' }
            & $find $(if ($r -ge 1 -or $throttled -ge 100) { 'High' } else { 'Medium' }) 'Health' 'Requests throttled' ('{0:N0} request(s) throttled ({1:N2}% of requests).' -f $throttled, $r) $fix
        }
        if ($serverErrors -gt 0 -and (& $rateOf $serverErrors) -ge 0.1) { & $find 'Medium' 'Health' 'Server errors' ('{0:N0} request(s) failed on the service side.' -f $serverErrors) 'Retry transient errors (the Service Bus SDKs do); check Resource Health and Azure status for the region if they persist.' }
        if ($userErrors -gt 0 -and (& $rateOf $userErrors) -ge 5) { & $find 'Low' 'Health' 'Many client errors' ('{0:N0} request(s) ({1:N1}%) failed because of the client: lost message locks, entities not found, quota exceeded or bad requests.' -f $userErrors, (& $rateOf $userErrors)) 'Look at the operational logs: renew locks for long processing (or lengthen LockDuration), and fix the callers using wrong entity names.' }
        if ($premium -and $null -ne $cpu -and $cpu -ge 60) { & $find $(if ($cpu -ge 80) { 'High' } else { 'Medium' }) 'Capacity' 'CPU close to its limit' "CPU peaked at $cpu% of $units messaging unit(s)." 'Add messaging units (or scale on CPU usage) before requests are throttled.' }
        if ($premium -and $null -ne $memory -and $memory -ge 60) { & $find $(if ($memory -ge 80) { 'High' } else { 'Medium' }) 'Capacity' 'Memory close to its limit' "Memory peaked at $memory% of $units messaging unit(s)." 'Add messaging units, and drain large backlogs - messages held in memory count against it.' }
        if ($tls -and $tls -notin '1.2', '1.3') { & $find 'High' 'Security' 'TLS below 1.2 accepted' "Minimum TLS version: $tls." 'Set the minimum TLS version to 1.2.' }
        if ($localAuth) { & $find 'Medium' 'Security' 'SAS keys allowed (local authentication)' "Shared access keys - $manageKeys namespace-wide with Manage rights - grant access that can't be traced to a user or app." 'Give apps Microsoft Entra ID identities with the Azure Service Bus Data Sender / Receiver roles, then turn off local authentication.' }
        if ($localAuth -and $manageKeys -gt 1) { & $find 'Low' 'Security' 'More than one namespace-wide Manage key' "$manageKeys SAS rules on the namespace have Manage rights - full control of every entity." 'Keep RootManageSharedAccessKey for emergencies only; give apps entity-level Send or Listen rules (or better, Entra ID roles).' }
        if ($network -eq 'Public' -and -not $endpoints) { & $find 'Medium' 'Security' 'Open to every network' 'Public network access is on, with no IP or virtual network rules and no private endpoint.' $(if ($premium) { 'Use private endpoints and disable public network access - or allow only the networks that need it.' } else { 'Allow only the IP ranges that need it (IP firewall); for private endpoints, move to Premium.' }) }
        if ($logsRead -and -not $logsTo) { & $find 'Medium' 'Security' 'No logs to Log Analytics' 'Operational and runtime audit logs aren''t sent to a workspace: who did what can''t be investigated.' 'Add a diagnostic setting sending the audit category group (or OperationalLogs and RuntimeAuditLogs) to a Log Analytics workspace.' }
        if ($premium -and -not $zoneRedundant) { & $find 'Medium' 'Resilience' 'Not zone redundant' 'A zone outage takes the namespace down.' 'Create Premium namespaces as zone redundant (in regions with availability zones); move the entities over.' }
        if ($premium -and -not $geoDr) { & $find 'Low' 'Resilience' 'No geo-disaster recovery' 'No alias pairs the namespace with one in another region, and no geo-replication.' 'Pair it with a namespace in another region (Geo-DR alias for metadata, or geo-replication for messages too) and connect through the alias.' }
        if ($tier -eq 'Basic') { & $find 'Low' 'Resilience' 'Basic tier' 'Basic has no topics, sessions, transactions, duplicate detection or auto-forwarding.' 'Use Standard (or Premium for production isolation and predictable performance).' }
        if ($premium -and $units -gt 1 -and $null -ne $cpu -and $cpu -lt 20 -and ($null -eq $memory -or $memory -lt 20)) { & $find 'Low' 'Cost' 'More messaging units than needed' "CPU peaked at $cpu% and memory at $(if ($null -ne $memory) { "$memory%" } else { '-' }) on $units messaging units." 'Scale down the messaging units - or scale them automatically on CPU usage.' }
        if ($metricsRead -and $requests -eq 0) { & $find 'Low' 'Cost' 'No requests in the period' 'Nothing sent to or received from the namespace.' 'Confirm it is still needed; delete it if not - Premium namespaces cost the same idle or busy.' }

        # --- Heat map: each signal 0-100 ----------------------------------------------------------------------------
        $cell = { param($Score) if ($null -eq $Score) { $null } else { @{ Score = [Math]::Round([Math]::Max(0, [Math]::Min(100, [double]$Score)), 1) } } }
        $share = { param([object[]] $Checks) 100.0 * @($Checks | Where-Object { $_ }).Count / [Math]::Max(1, $Checks.Count) }
        $messageIssues = @($findings | Where-Object { $_.ResourceId -eq $id -and $_.Signal -eq 'Messages' } | ForEach-Object { $_.Entity } | Select-Object -Unique).Count
        $securityChecks = @(($tls -notin '1.0', '1.1'), (-not $localAuth), ($network -ne 'Public' -or $endpoints -gt 0))
        if ($logsRead) { $securityChecks += [bool]$logsTo }
        $resilienceChecks = @(($tier -ne 'Basic'))
        if ($premium) { $resilienceChecks += @($zoneRedundant, $geoDr) }
        $idleEntities = @($findings | Where-Object { $_.ResourceId -eq $id -and $_.Finding -eq 'Not used for 30 days or more' }).Count
        $costChecks = @((-not ($metricsRead -and $requests -eq 0)), ($idleEntities -eq 0))
        if ($premium -and $null -ne $cpu) { $costChecks += -not ($units -gt 1 -and $cpu -lt 20 -and ($null -eq $memory -or $memory -lt 20)) }
        $usage = @(@($cpu, $memory) | Where-Object { $null -ne $_ })
        $scores = [ordered]@{
            Health     = $(if ($requests) { 100 - (& $rateOf $throttled) * 20 - (& $rateOf $serverErrors) * 10 } else { $null })
            Capacity   = $(if ($usage.Count) { 100 - [Math]::Max(0, ($usage | Measure-Object -Maximum).Maximum - 50) * 2 } else { $null })
            Messages   = $(if ($entitiesRead -and $mine.Count) { 100.0 * ($mine.Count - $messageIssues) / $mine.Count } else { $null })
            Security   = & $share $securityChecks
            Resilience = & $share $resilienceChecks
            Cost       = & $share $costChecks
        }
        $cells = @(foreach ($signal in $signals) { & $cell $scores[$signal] })
        $scored = @($cells | Where-Object { $_ })
        $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1) } else { $null }
        $heatRows.Add(@{ Label = $name; Filter = $name; Cells = $cells; Total = $(if ($null -ne $overall) { @{ Score = $overall } } else { $null }); Overall = $overall })

        $namespaceRows.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.ServiceBusAssessment'
                Namespace        = $name
                Score            = $overall
                Tier             = $tier
                MessagingUnits   = $(if ($premium) { $units } else { $null })
                Queues           = @($mine | Where-Object { $_.Type -eq 'Queue' }).Count
                Topics           = @($mine | Where-Object { $_.Type -eq 'Topic' }).Count
                Subscriptions    = @($mine | Where-Object { $_.Type -eq 'Subscription' }).Count
                ActiveMessages   = $active
                DeadLetters      = $dead
                Scheduled        = $scheduledTotal
                SizeMB           = & $round (& $sumOf @($mine | Where-Object { $_.Type -ne 'Subscription' }) 'SizeMB') 2
                FullestPct       = $(if ($fullest.Count) { $fullest[0] } else { $null })
                Requests         = $requests
                Successful       = $successful
                Throttled        = $throttled
                ServerErrors     = $serverErrors
                UserErrors       = $userErrors
                ErrorRate        = $(if ($requests) { & $round (100.0 * ($throttled + $serverErrors) / $requests) 2 } else { $null })
                IncomingMessages = $incoming
                OutgoingMessages = $outgoing
                CpuMax           = $cpu
                MemoryMax        = $memory
                MinTls           = $tls
                LocalAuth        = $localAuth
                ManageKeys       = $manageKeys
                Network          = $network
                PrivateEndpoints = $endpoints
                Encryption       = $(if ($cmk) { 'Customer-managed key' } else { 'Microsoft-managed key' })
                Identity         = $identity
                ZoneRedundant    = $zoneRedundant
                GeoDr            = $(if ($replicas) { 'Geo-replication' } elseif ($alias) { 'Alias' } else { '' })
                LogsTo           = $(if ($logsTo) { if ($WorkspaceName.Contains($logsTo)) { $WorkspaceName[$logsTo] } else { ($logsTo -split '/')[-1] } } else { '' })
                MetricsError     = $(if ($core -and $core.Error) { [string]$core.Error } else { '' })
                Findings         = @($findings | Where-Object { $_.ResourceId -eq $id }).Count
                Location         = [string]$n['location']
                ResourceGroup    = [string]$n['resourceGroup']
                Subscription     = & $subName ([string]$n['subscriptionId'])
                ResourceId       = $id
            })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $worst = @($heatRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.Overall) { 101 } else { $_.Overall } } }, Label | Select-Object -First 40)
    $total = { param([string] $Property) [long](& $sumOf $namespaceRows.ToArray() $Property) }
    @{
        Namespaces = $namespaceRows.ToArray()
        Entities   = $entityRows.ToArray()
        Findings   = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Namespace, Entity, Finding)
        HeatMap    = @{ Title = 'Service Bus namespaces by signal'; RowHeader = 'Namespace'; Columns = $signals; Rows = $worst; Table = 'findings'; RowKey = 'Namespace'; ColumnKey = 'Signal'; ConsoleColumns = 6
            Note = "0-100 per signal, worst namespaces first$(if ($heatRows.Count -gt 40) { " (40 of $($heatRows.Count))" }): health, capacity (Premium), messages, security, resilience, cost. Click a cell for its findings." }
        Messages   = $messageTotals
        Stats      = @{
            Namespaces   = $namespaceRows.Count
            Entities     = $entityRows.Count
            Requests     = & $total 'Requests'
            Throttled    = & $total 'Throttled'
            Active       = [long]$messageTotals['Active']
            DeadLetters  = [long]$messageTotals['Dead-lettered']
            Public       = @($namespaceRows | Where-Object { $_.Network -eq 'Public' -and -not $_.PrivateEndpoints }).Count
            LocalAuth    = @($namespaceRows | Where-Object { $_.LocalAuth }).Count
            High         = @($findings | Where-Object { $_.Severity -eq 'High' }).Count
        }
    }
}
