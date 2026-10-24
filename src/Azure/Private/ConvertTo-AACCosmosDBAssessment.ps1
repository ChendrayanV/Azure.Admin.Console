function ConvertTo-AACCosmosDBAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACCosmosDBAssessment read into per-account
        availability, requests, throughput, storage, posture and resilience,
        per-container throughput, findings and a heat map.
    .DESCRIPTION
        No Azure calls. Per account (AAC.CosmosDBAssessment):
          health      over the period: ServiceAvailability (average %),
                      Requests and their status codes - Throttled (429),
                      ServerErrors (5xx), ClientErrors (other 4xx but 404,
                      409 and 412, which are often normal) - ThrottleRate,
                      RequestUnits, NormalizedRuMax (the busiest partition's
                      share of its throughput), LatencyMs (server side)
          storage     the latest value: DataGB, IndexGB, Documents
          throughput  CapacityMode (Provisioned, Serverless), Databases,
                      Containers, ProvisionedRU (manual), AutoscaleMaxRU
          posture     Api, Network (Private, Firewall, Public),
                      PrivateEndpoints, LocalAuth (keys allowed), MinTls,
                      Encryption, Defender, LogsTo
          resilience  Regions, WriteRegions, AutomaticFailover,
                      MultiRegionWrites, ZoneRedundant, Consistency, Backup,
                      BackupRedundancy
        Per container (AAC.CosmosDBContainer): database, partition key,
        throughput mode (Autoscale, Manual, Shared database, Serverless) and
        RU/s, default TTL, analytical store, indexing mode.
        Findings (AAC.CosmosDBFinding: Severity, Account, Database,
        Container, Signal, Finding, Detail, Recommendation) - Signal is the
        heat map's column: Availability, Throttling, Errors, Security,
        Resilience, Cost.
        Returns @{ Accounts; Containers; Findings; HeatMap; StatusCodes; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Account,

        # Read-AACCosmosDBResource's result, by account ID.
        [hashtable] $Resource = @{},

        # Read-AACMetric's result (Requests, Usage, Availability, Latency, Storage), by account ID.
        [hashtable] $Metric = @{},

        [AllowEmptyCollection()]
        [object[]] $Pricing = @(),

        [AllowEmptyCollection()]
        [object[]] $Alert = @(),

        # Workspace resource ID (lower case) -> name.
        [hashtable] $WorkspaceName = @{},

        [hashtable] $SubscriptionName = @{}
    )

    $at = { param($Row, [string[]] $Keys) Get-AACMember -InputObject $Row -Key $Keys }
    $sum = { param([object[]] $Points, [string] $Field) $t = 0.0; foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { $t += [double]$v } }; $t }
    $values = { param([object[]] $Points, [string] $Field) @(foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { [double]$v } }) }
    $mean = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Average).Average } else { $null } }
    $peak = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Maximum).Maximum } else { $null } }
    $latest = { param([object[]] $Points) $v = @(& $values $Points 'total'); if (-not $v.Count) { $v = @(& $values $Points 'maximum') }; if ($v.Count) { $v[-1] } else { $null } }
    # Measure-Object returns nothing for no input (and .Sum then fails under StrictMode): this returns 0.
    $sumOf = { param([object[]] $Rows, [string] $Property) $t = 0.0; foreach ($row in $Rows) { if ($null -ne $row.$Property) { $t += [double]$row.$Property } }; $t }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $gb = { param($Bytes) if ($null -eq $Bytes) { $null } else { [Math]::Round([double]$Bytes / 1GB, 2) } }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $call = { param([string] $Id, [string] $Key) if ($Metric.Contains($Id) -and $Metric[$Id].Contains($Key)) { $Metric[$Id][$Key] } else { $null } }
    $pointsOf = { param($Answer, [string] $Name) @(if ($Answer -and -not $Answer.Error) { foreach ($s in $Answer.Series) { if ($s.Name -eq $Name) { $s.Points } } }) }
    $itemsOf = { param($Answer) @(if ($Answer -and -not $Answer['Error']) { $Answer['Items'] | Where-Object { $_ } }) }
    # A throughputSettings answer: @{ Mode = Manual / Autoscale; RU } - or $null when none is set at that level.
    $throughputOf = {
        param($Answer)
        if (-not $Answer -or $Answer['Error'] -or [int]$Answer['Status'] -ne 200) { return $null }
        $res = & $at $Answer 'Body', 'properties', 'resource'
        $auto = & $at $res 'autoscaleSettings', 'maxThroughput'
        if ($auto) { return @{ Mode = 'Autoscale'; RU = [int]$auto } }
        $manual = & $at $res 'throughput'
        if ($manual) { return @{ Mode = 'Manual'; RU = [int]$manual } }
        $null
    }
    $defender = @{}
    foreach ($p in $Pricing) { $defender[[string]$p['subscriptionId']] = [string]$p['tier'] }
    $alerts = @{}
    foreach ($a in $Alert) { $id = [string]$a['resourceId']; $alerts[$id] = 1 + $(if ($alerts.Contains($id)) { $alerts[$id] } else { 0 }) }

    $findings = [System.Collections.Generic.List[object]]::new()
    $accountRows = [System.Collections.Generic.List[object]]::new()
    $containerRows = [System.Collections.Generic.List[object]]::new()
    $heatRows = [System.Collections.Generic.List[object]]::new()
    $signals = @('Availability', 'Throttling', 'Errors', 'Security', 'Resilience', 'Cost')
    $statusTotals = [ordered]@{ Success = 0.0; 'Throttled (429)' = 0.0; 'Server (5xx)' = 0.0; 'Client (4xx)' = 0.0; 'Not found, conflict (404, 409, 412)' = 0.0 }

    foreach ($c in @($Account | Sort-Object -Property { [string]$_['name'] })) {
        $id = [string]$c['id']
        $name = [string]$c['name']
        $p = $c['properties']
        $capabilities = @(@(& $at $p 'capabilities') | ForEach-Object { [string](& $at $_ 'name') })
        $apiName = if ([string]$c['kind'] -eq 'MongoDB' -or $capabilities -contains 'EnableMongo') { 'MongoDB' } elseif ($capabilities -contains 'EnableCassandra') { 'Cassandra' } elseif ($capabilities -contains 'EnableGremlin') { 'Gremlin' } elseif ($capabilities -contains 'EnableTable') { 'Table' } else { 'NoSQL' }
        $serverless = $capabilities -contains 'EnableServerless'
        $find = {
            param([string] $Severity, [string] $Signal, [string] $Title, [string] $Detail, [string] $Fix, [string] $Database = '', [string] $Container = '')
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.CosmosDBFinding'; Severity = $Severity; Account = $name; Database = $Database; Container = $Container; Signal = $Signal; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceGroup = [string]$c['resourceGroup']; Subscription = & $subName ([string]$c['subscriptionId']); ResourceId = $id })
        }

        # --- Health: Azure Monitor over the period ------------------------------------------------------------------
        $requestsCall = & $call $id 'Requests'
        $metricsRead = [bool]($requestsCall -and -not $requestsCall.Error)
        $codes = @{ Success = 0.0; Throttled = 0.0; Server = 0.0; Client = 0.0; Benign = 0.0 }
        foreach ($series in @(if ($metricsRead) { $requestsCall.Series })) {
            $code = [string]$series.Dims['statuscode']
            $n = & $sum $series.Points 'count'
            if (-not $n) { $n = & $sum $series.Points 'total' }
            if (-not $n) { continue }
            $bucket = switch -Regex ($code) { '^429$' { 'Throttled'; break } '^5' { 'Server'; break } '^(404|409|412)$' { 'Benign'; break } '^4' { 'Client'; break } default { 'Success' } }
            $codes[$bucket] += $n
        }
        $statusTotals['Success'] += $codes.Success; $statusTotals['Throttled (429)'] += $codes.Throttled; $statusTotals['Server (5xx)'] += $codes.Server; $statusTotals['Client (4xx)'] += $codes.Client; $statusTotals['Not found, conflict (404, 409, 412)'] += $codes.Benign
        $requests = [long]($codes.Success + $codes.Throttled + $codes.Server + $codes.Client + $codes.Benign)
        $rateOf = { param([double] $Count) if ($requests) { 100.0 * $Count / $requests } else { 0 } }
        $usage = & $call $id 'Usage'
        $requestUnits = [long](& $sum (& $pointsOf $usage 'TotalRequestUnits') 'total')
        $normalized = & $round (& $peak (& $values (& $pointsOf $usage 'NormalizedRUConsumption') 'maximum'))
        $availability = & $round (& $mean (& $values (& $pointsOf (& $call $id 'Availability') 'ServiceAvailability') 'average')) 3
        $latency = & $round (& $mean (& $values (& $pointsOf (& $call $id 'Latency') 'ServerSideLatency') 'average')) 2
        $storage = & $call $id 'Storage'
        $documents = & $latest (& $pointsOf $storage 'DocumentCount')

        # --- Databases, containers and throughput -------------------------------------------------------------------
        $read = if ($Resource.Contains($id)) { $Resource[$id] } else { @{ Logs = $null; Error = 'Not read.'; Databases = @() } }
        $manualRu = 0; $autoscaleRu = 0; $containerCount = 0
        foreach ($db in @($read.Databases)) {
            $shared = if ($serverless) { $null } else { & $throughputOf $db.Throughput }
            if ($shared) { if ($shared.Mode -eq 'Autoscale') { $autoscaleRu += $shared.RU } else { $manualRu += $shared.RU } }
            $smallDedicated = 0
            foreach ($container in @($db.Containers)) {
                $containerCount++
                $own = if ($serverless) { $null } else { & $throughputOf $container.Throughput }
                if ($own) { if ($own.Mode -eq 'Autoscale') { $autoscaleRu += $own.RU } else { $manualRu += $own.RU; if ($own.RU -le 1000) { $smallDedicated++ } } }
                $res = & $at $container.Resource 'resource'
                $partitionKey = switch ($apiName) {
                    'MongoDB' { (@((& $at $res 'shardKey').Keys) -join ', ') }
                    'Cassandra' { (@(@(& $at $res 'schema', 'partitionKeys') | ForEach-Object { [string](& $at $_ 'name') }) -join ', ') }
                    'Table' { 'PartitionKey' }
                    default { (@(& $at $res 'partitionKey', 'paths') -join ', ') }
                }
                $containerRows.Add([pscustomobject][ordered]@{
                        PSTypeName      = 'AAC.CosmosDBContainer'
                        Account         = $name
                        Database        = $db.Name
                        Container       = $container.Name
                        Api             = $apiName
                        PartitionKey    = $partitionKey
                        ThroughputMode  = $(if ($serverless) { 'Serverless' } elseif ($own) { $own.Mode } elseif ($shared) { 'Shared database' } else { '' })
                        RU              = $(if ($own) { $own.RU } elseif ($shared) { $shared.RU } else { $null })
                        DefaultTtl      = & $at $res 'defaultTtl'
                        AnalyticalStore = $null -ne (& $at $res 'analyticalStorageTtl')
                        IndexingMode    = [string](& $at $res 'indexingPolicy', 'indexingMode')
                        ResourceGroup   = [string]$c['resourceGroup']
                        Subscription    = & $subName ([string]$c['subscriptionId'])
                    })
            }
            if (-not $shared -and $smallDedicated -ge 4) { & $find 'Low' 'Cost' 'Many small containers with their own throughput' "$smallDedicated containers in '$($db.Name)' each have 1,000 RU/s or less of their own - each billed at least 400 RU/s, used or not." 'Share throughput at the database level for small, quiet containers - they then draw from one pool.' $db.Name }
        }

        # --- Posture --------------------------------------------------------------------------------------------
        $endpoints = @(@(& $at $p 'privateEndpointConnections') | Where-Object { $_ -and [string](& $at $_ 'properties', 'privateLinkServiceConnectionState', 'status') -eq 'Approved' }).Count
        $ipRules = @(& $at $p 'ipRules' | Where-Object { $_ }).Count
        $vnetRules = if ([string](& $at $p 'isVirtualNetworkFilterEnabled') -eq 'True') { @(& $at $p 'virtualNetworkRules' | Where-Object { $_ }).Count } else { 0 }
        $network = if ([string](& $at $p 'publicNetworkAccess') -eq 'Disabled') { 'Private' } elseif ($ipRules -or $vnetRules) { 'Firewall' } else { 'Public' }
        $localAuth = [string](& $at $p 'disableLocalAuth') -ne 'True'
        $metadataByKey = [string](& $at $p 'disableKeyBasedMetadataWriteAccess') -ne 'True'
        $tls = [string](& $at $p 'minimalTlsVersion')
        $cmk = [bool](& $at $p 'keyVaultKeyUri')
        $plan = [string]$defender[[string]$c['subscriptionId']]
        $logsTo = $null
        foreach ($diagnostic in (& $itemsOf $read.Logs)) {
            $dp = & $at $diagnostic 'properties'
            $workspace = ([string](& $at $dp 'workspaceId')).ToLowerInvariant()
            if (-not $workspace) { continue }
            $on = @(@(& $at $dp 'logs') | Where-Object { $_ -and (& $at $_ 'enabled') -eq $true -and ([string](& $at $_ 'category') -match 'Requests$|^QueryRuntimeStatistics$' -or [string](& $at $_ 'categoryGroup') -in 'audit', 'allLogs') }).Count
            if ($on) { $logsTo = $workspace; break }
        }
        $logsRead = [bool]($read.Logs -and -not $read.Logs['Error'])

        # --- Resilience -------------------------------------------------------------------------------------------
        $locations = @(@(& $at $p 'locations') | Where-Object { $_ } | Sort-Object -Property { [int](& $at $_ 'failoverPriority') })
        $regions = @($locations | ForEach-Object { [string](& $at $_ 'locationName') })
        $multiWrite = [string](& $at $p 'enableMultipleWriteLocations') -eq 'True'
        $autoFailover = [string](& $at $p 'enableAutomaticFailover') -eq 'True'
        $zoneRedundant = @($locations | Where-Object { [string](& $at $_ 'isZoneRedundant') -eq 'True' }).Count -gt 0
        $consistency = [string](& $at $p 'consistencyPolicy', 'defaultConsistencyLevel')
        $backupType = [string](& $at $p 'backupPolicy', 'type')
        $backup = if ($backupType -eq 'Continuous') { "Continuous $([string](& $at $p 'backupPolicy', 'continuousModeProperties', 'tier') -replace 'Continuous', '')".Trim() } elseif ($backupType) { $minutes = & $at $p 'backupPolicy', 'periodicModeProperties', 'backupIntervalInMinutes'; "Periodic$(if ($minutes) { " every $([Math]::Round([double]$minutes / 60, 1)) h" })" } else { '' }
        $backupRedundancy = [string](& $at $p 'backupPolicy', 'periodicModeProperties', 'backupStorageRedundancy')

        # --- Findings ---------------------------------------------------------------------------------------------
        if ($null -ne $availability -and $requests -and $availability -lt 99.99) { & $find $(if ($availability -lt 99.9) { 'High' } else { 'Medium' }) 'Availability' 'Availability below 99.99%' "Service availability averaged $availability% over the period." 'Check Resource Health and the failed requests by status code; add a region with automatic failover, and retry transient errors in the SDK.' }
        if ($codes.Throttled -gt 0) {
            $r = & $rateOf $codes.Throttled
            & $find $(if ($r -ge 1) { 'High' } else { 'Medium' }) 'Throttling' 'Requests rate limited (429)' ('{0:N0} request(s) rate limited ({1:N2}% of requests){2}.' -f $codes.Throttled, $r, $(if ($null -ne $normalized) { "; the busiest partition reached $normalized% of its throughput" } else { '' })) $(if ($serverless) { 'Serverless accounts have a per-container ceiling: spread the load with a better partition key, or move to provisioned throughput.' } else { 'Raise the RU/s or use autoscale; spread hot partitions with a better partition key; the SDKs retry 429s - make sure their retry limits are high enough.' })
        }
        elseif ($null -ne $normalized -and $normalized -ge 90 -and -not $serverless) { & $find 'Low' 'Throttling' 'Running close to its throughput' "The busiest partition reached $normalized% of its throughput, without rate limiting yet." 'Watch for 429s; autoscale absorbs peaks without paying for them all the time.' }
        if ($codes.Server -gt 0 -and (& $rateOf $codes.Server) -ge 0.1) { & $find 'Medium' 'Errors' 'Server errors (5xx)' ('{0:N0} request(s) failed on the service side.' -f $codes.Server) 'Retry transient errors (the SDKs do); check Resource Health and the request timeouts (408) and service unavailable (503) in the logs.' }
        if ($null -ne $latency -and $latency -ge 10) { & $find 'Low' 'Errors' 'Slow server-side latency' "Server-side latency averaged $latency ms." 'Look at the slow queries (QueryRuntimeStatistics): cross-partition queries, missing indexes or large documents; point reads by id and partition key are fastest.' }
        if ($tls -and $tls -notin 'Tls12', 'Tls13') { & $find 'High' 'Security' 'TLS below 1.2 accepted' "Minimum TLS version: $tls." 'Set the minimum TLS version to 1.2.' }
        if ($network -eq 'Public' -and -not $endpoints) { & $find 'High' 'Security' 'Open to every network' 'Public network access is on, with no IP firewall, virtual network rule or private endpoint.' 'Use private endpoints and disable public network access - or allow only the networks that need it.' }
        if ($localAuth) { & $find 'Medium' 'Security' 'Account keys allowed (local authentication)' 'The primary and secondary keys give full access to every database and can''t be traced to a user or app.' 'Give apps Microsoft Entra ID identities with Cosmos DB data-plane roles, then turn off local authentication.' }
        if ($localAuth -and $metadataByKey) { & $find 'Low' 'Security' 'Keys can change databases and containers' 'Anyone with a key can create, change or delete databases and containers (and their throughput).' 'Turn on disableKeyBasedMetadataWriteAccess so those changes need Azure RBAC.' }
        if ($logsRead -and -not $logsTo) { & $find 'Medium' 'Security' 'No logs to Log Analytics' 'Data-plane and control-plane requests aren''t sent to a workspace: who read or changed data can''t be investigated.' 'Add a diagnostic setting sending the request categories (DataPlaneRequests, ControlPlaneRequests, QueryRuntimeStatistics) to a Log Analytics workspace, in resource-specific tables.' }
        if ($plan -ne 'Standard') { & $find 'Low' 'Security' 'Defender for Azure Cosmos DB off' 'SQL injection, unusual access and data exfiltration raise no alert.' 'Turn on Microsoft Defender for Azure Cosmos DB for the subscription.' }
        if ($alerts.Contains($id)) { & $find 'High' 'Security' 'Defender alerts in the last 30 days' "$($alerts[$id]) alert(s) on this account." 'Investigate them in Defender for Cloud > Security alerts.' }
        if ($regions.Count -eq 1) { & $find 'Medium' 'Resilience' 'Single region' "Only in $($regions[0]): a regional outage makes the data unavailable." 'Add a second region (reads stay local, and the account can fail over).' }
        elseif ($regions.Count -gt 1 -and -not $multiWrite -and -not $autoFailover) { & $find 'Medium' 'Resilience' 'No automatic failover' "$($regions.Count) regions, but if the write region goes down Azure won't fail over by itself." 'Turn on service-managed failover, and set the failover priorities.' }
        if ($regions.Count -and -not $zoneRedundant) { & $find 'Low' 'Resilience' 'No availability zones' 'No region uses availability zones: a zone outage can interrupt the account.' 'Turn on zone redundancy for the regions that support it (set when a region is added).' }
        if ($backupType -eq 'Periodic') { & $find 'Low' 'Resilience' 'Periodic backup only' "Backups $($backup.ToLowerInvariant()); restoring means a support request, to the last backup." 'Move to continuous backup: point-in-time restore to any second in the last 7 or 30 days, by yourself.' }
        if ($backupType -eq 'Periodic' -and $backupRedundancy -eq 'Local') { & $find 'Low' 'Resilience' 'Backups stored in one datacentre' 'Periodic backups use locally redundant storage.' 'Store backups geo-redundant (or zone-redundant), or move to continuous backup.' }
        if ($consistency -eq 'Strong' -and $regions.Count -gt 1) { & $find 'Low' 'Resilience' 'Strong consistency across regions' "Every write waits for $($regions.Count) regions: slower writes, and writes stop if a region can't be reached." 'Use Bounded staleness or Session unless the app really needs Strong.' }
        if (-not $serverless -and $manualRu -ge 1000 -and $null -ne $normalized -and $normalized -lt 20 -and $requests) { & $find 'Low' 'Cost' 'Throughput higher than needed' ('{0:N0} RU/s provisioned (manual), but the busiest partition peaked at {1}% of it.' -f $manualRu, $normalized) 'Lower the RU/s, or switch to autoscale (it scales down to 10% when idle) - or serverless for spiky, light use.' }
        if ($metricsRead -and $requests -eq 0) { & $find 'Low' 'Cost' 'No requests in the period' 'Nothing read or wrote the account.' 'Confirm it is still needed; provisioned throughput is billed whether used or not.' }

        # --- Heat map: each signal 0-100 ----------------------------------------------------------------------------
        $cell = { param($Score) if ($null -eq $Score) { $null } else { @{ Score = [Math]::Round([Math]::Max(0, [Math]::Min(100, [double]$Score)), 1) } } }
        $share = { param([object[]] $Checks) 100.0 * @($Checks | Where-Object { $_ }).Count / [Math]::Max(1, $Checks.Count) }
        $securityChecks = @(($tls -notin 'Tls', 'Tls11'), ($network -ne 'Public' -or $endpoints -gt 0), (-not $localAuth), ($plan -eq 'Standard'))
        if ($logsRead) { $securityChecks += [bool]$logsTo }
        $resilienceChecks = @(($regions.Count -gt 1), ($multiWrite -or $autoFailover -or $regions.Count -le 1), $zoneRedundant, ($backupType -eq 'Continuous'))
        $costChecks = @((-not ($metricsRead -and $requests -eq 0)), (-not ($manualRu -ge 1000 -and $null -ne $normalized -and $normalized -lt 20 -and $requests)), (@($findings | Where-Object { $_.ResourceId -eq $id -and $_.Finding -like 'Many small containers*' }).Count -eq 0))
        $scores = [ordered]@{
            Availability = $(if ($null -ne $availability -and $requests) { ($availability - 99) * 100 } else { $null })
            Throttling   = $(if ($requests) { 100 - (& $rateOf $codes.Throttled) * 20 } else { $null })
            Errors       = $(if ($requests) { 100 - (& $rateOf $codes.Server) * 10 - $(if ($null -ne $latency -and $latency -ge 10) { 10 } else { 0 }) } else { $null })
            Security     = & $share $securityChecks
            Resilience   = & $share $resilienceChecks
            Cost         = & $share $costChecks
        }
        $cells = @(foreach ($signal in $signals) { & $cell $scores[$signal] })
        $scored = @($cells | Where-Object { $_ })
        $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1) } else { $null }
        $heatRows.Add(@{ Label = $name; Filter = $name; Cells = $cells; Total = $(if ($null -ne $overall) { @{ Score = $overall } } else { $null }); Overall = $overall })

        $accountRows.Add([pscustomobject][ordered]@{
                PSTypeName        = 'AAC.CosmosDBAssessment'
                Account           = $name
                Score             = $overall
                Api               = $apiName
                CapacityMode      = $(if ($serverless) { 'Serverless' } else { 'Provisioned' })
                Regions           = $regions -join ', '
                RegionCount       = $regions.Count
                WriteRegions      = $(if ($multiWrite) { $regions.Count } else { [Math]::Min(1, $regions.Count) })
                AutomaticFailover = $autoFailover
                MultiRegionWrites = $multiWrite
                ZoneRedundant     = $zoneRedundant
                Consistency       = $consistency
                Backup            = $backup
                BackupRedundancy  = $backupRedundancy
                Databases         = @($read.Databases | Where-Object { $_.Name }).Count
                Containers        = $containerCount
                ProvisionedRU     = $(if ($serverless) { $null } else { $manualRu })
                AutoscaleMaxRU    = $(if ($serverless) { $null } else { $autoscaleRu })
                Requests          = $requests
                Throttled         = [long]$codes.Throttled
                ThrottleRate      = $(if ($requests) { & $round (& $rateOf $codes.Throttled) 2 } else { $null })
                ServerErrors      = [long]$codes.Server
                ClientErrors      = [long]$codes.Client
                Availability      = $availability
                NormalizedRuMax   = $normalized
                RequestUnits      = $requestUnits
                LatencyMs         = $latency
                DataGB            = & $gb (& $latest (& $pointsOf $storage 'DataUsage'))
                IndexGB           = & $gb (& $latest (& $pointsOf $storage 'IndexUsage'))
                Documents         = $(if ($null -ne $documents) { [long]$documents } else { $null })
                Network           = $network
                PrivateEndpoints  = $endpoints
                LocalAuth         = $localAuth
                MinTls            = $tls
                Encryption        = $(if ($cmk) { 'Customer-managed key' } else { 'Microsoft-managed key' })
                Defender          = $(if ($plan -eq 'Standard') { 'On' } elseif ($plan) { 'Off' } else { 'Unknown' })
                LogsTo            = $(if ($logsTo) { if ($WorkspaceName.Contains($logsTo)) { $WorkspaceName[$logsTo] } else { ($logsTo -split '/')[-1] } } else { '' })
                FreeTier          = [string](& $at $p 'enableFreeTier') -eq 'True'
                MetricsError      = $(if ($requestsCall -and $requestsCall.Error) { [string]$requestsCall.Error } else { '' })
                ResourcesError    = [string]$read.Error
                Findings          = @($findings | Where-Object { $_.ResourceId -eq $id }).Count
                Location          = [string]$c['location']
                ResourceGroup     = [string]$c['resourceGroup']
                Subscription      = & $subName ([string]$c['subscriptionId'])
                ResourceId        = $id
            })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $worst = @($heatRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.Overall) { 101 } else { $_.Overall } } }, Label | Select-Object -First 40)
    $total = { param([string] $Property) [long](& $sumOf $accountRows.ToArray() $Property) }
    @{
        Accounts    = $accountRows.ToArray()
        Containers  = $containerRows.ToArray()
        Findings    = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Account, Database, Container, Finding)
        HeatMap     = @{ Title = 'Cosmos DB accounts by signal'; RowHeader = 'Account'; Columns = $signals; Rows = $worst; Table = 'findings'; RowKey = 'Account'; ColumnKey = 'Signal'; ConsoleColumns = 6
            Note = "0-100 per signal, worst accounts first$(if ($heatRows.Count -gt 40) { " (40 of $($heatRows.Count))" }): availability, throttling, errors and latency, security, resilience, cost. Click a cell for its findings." }
        StatusCodes = $statusTotals
        Stats       = @{
            Accounts    = $accountRows.Count
            Containers  = $containerRows.Count
            Requests    = & $total 'Requests'
            Throttled   = & $total 'Throttled'
            RU          = (& $total 'ProvisionedRU') + (& $total 'AutoscaleMaxRU')
            DataGB      = [Math]::Round((& $sumOf $accountRows.ToArray() 'DataGB'), 2)
            Public      = @($accountRows | Where-Object { $_.Network -eq 'Public' -and -not $_.PrivateEndpoints }).Count
            SingleRegion = @($accountRows | Where-Object { $_.RegionCount -eq 1 }).Count
            LocalAuth   = @($accountRows | Where-Object { $_.LocalAuth }).Count
            High        = @($findings | Where-Object { $_.Severity -eq 'High' }).Count
        }
    }
}
