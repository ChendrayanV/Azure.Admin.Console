function ConvertTo-AACStorageAccountAssessment {
    <#
    .SYNOPSIS
        Turns what Invoke-AACStorageAccountAssessment read into per-account
        health, capacity, posture, data protection, findings and a heat map.
    .DESCRIPTION
        No Azure calls. Per account (AAC.StorageAccountAssessment):
          health      the workbook's Overview tab: Availability (average %),
                      Transactions, Successes, the failures by response type -
                      Throttled (ClientThrottling*, ServerBusy*),
                      ServerErrors (ServerTimeout, ServerOther), AuthErrors
                      (Authorization, Authentication), NetworkErrors
                      (Network, ClientTimeout) and ClientErrors (ClientOther:
                      mostly 404 and 409 - often normal) - ErrorRate (% of
                      transactions: all but ClientOther), E2ELatencyMs,
                      ServerLatencyMs, ClientLatencyMs (the difference: time
                      spent between the client and the service), IngressGB,
                      EgressGB, ResponseTypes
          capacity    the workbook's Capacity tab (latest value): UsedGB,
                      BlobGB, FileGB, QueueGB, TableGB, Blobs, Containers,
                      FileShares
          posture     Kind, Sku, Redundancy, AccessTier, HttpsOnly, MinTls,
                      BlobAnonymousAccess, SharedKeyAccess, Network (Private,
                      Firewall, Public), PrivateEndpoints,
                      CrossTenantReplication, Encryption (Microsoft or
                      customer-managed keys), KeyAgeDays, KeyExpiryPolicy,
                      SasExpiryPolicy, Defender, LogsTo
          protection  BlobSoftDeleteDays, ContainerSoftDeleteDays, Versioning,
                      ChangeFeed, PointInTimeRestore, ShareSoftDeleteDays,
                      LifecycleRules
        Findings (AAC.StorageAccountFinding: Severity, Account, Signal,
        Finding, Detail, Recommendation) - Signal is the heat map's column:
        Availability, Errors, Throttling, Latency, Security, Protection, Cost.
        The heat map scores each account 0-100 per signal.
        Returns @{ Accounts; Findings; HeatMap; ResponseTypes; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Account,

        # Read-AACMetric's result for the Overview calls (Core, Responses), by account ID.
        [hashtable] $Metric = @{},

        # Read-AACMetric's result for the Capacity calls, by account or service ID.
        [hashtable] $Capacity = @{},

        # Read-AACStorageAccountSetting's result.
        [hashtable] $Setting = @{},

        [AllowEmptyCollection()]
        [object[]] $Pricing = @(),

        [AllowEmptyCollection()]
        [object[]] $Alert = @(),

        # Workspace resource ID (lower case) -> name.
        [hashtable] $WorkspaceName = @{},

        [hashtable] $SubscriptionName = @{},

        # How long the metrics cover, in hours (to judge idle and hot-tier use per day).
        [double] $Hours = 24,

        [datetime] $Now = [datetime]::UtcNow
    )

    $at = { param($Row, [string[]] $Keys) Get-AACMember -InputObject $Row -Key $Keys }
    $sum = { param([object[]] $Points, [string] $Field) $t = 0.0; foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { $t += [double]$v } }; $t }
    $values = { param([object[]] $Points, [string] $Field) @(foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { [double]$v } }) }
    $mean = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Average).Average } else { $null } }
    $latest = { param([object[]] $Points) $v = @(& $values $Points 'average'); if ($v.Count) { $v[-1] } else { $null } }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $gb = { param($Bytes) if ($null -eq $Bytes) { $null } else { [Math]::Round([double]$Bytes / 1GB, 2) } }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $call = { param([hashtable] $From, [string] $Id, [string] $Key) if ($From.Contains($Id) -and $From[$Id].Contains($Key)) { $From[$Id][$Key] } else { $null } }
    # One metric's points from a call, summed over its series.
    $pointsOf = { param($Answer, [string] $Name) @(if ($Answer -and -not $Answer.Error) { foreach ($s in $Answer.Series) { if ($s.Name -eq $Name) { $s.Points } } }) }
    $ok = { param($Answer) [bool]($Answer -and $Answer['Status'] -eq 200 -and -not $Answer['Error']) }
    $defender = @{}
    foreach ($p in $Pricing) { $defender[[string]$p['subscriptionId']] = [string]$p['tier'] }
    $alerts = @{}
    foreach ($a in $Alert) { $id = [string]$a['resourceId']; $alerts[$id] = 1 + $(if ($alerts.Contains($id)) { $alerts[$id] } else { 0 }) }
    $days = [Math]::Max($Hours / 24, 1 / 24)

    $findings = [System.Collections.Generic.List[object]]::new()
    $responseTotals = [ordered]@{ Success = 0.0; Throttling = 0.0; Server = 0.0; Authorization = 0.0; Network = 0.0; 'Client (404, 409...)' = 0.0 }
    $accountRows = [System.Collections.Generic.List[object]]::new()
    $heatRows = [System.Collections.Generic.List[object]]::new()
    $signals = @('Availability', 'Errors', 'Throttling', 'Latency', 'Security', 'Protection', 'Cost')

    foreach ($s in @($Account | Sort-Object -Property { [string]$_['name'] })) {
        $id = [string]$s['id']
        $name = [string]$s['name']
        $p = $s['properties']
        $kind = [string]$s['kind']
        $hasBlob = $kind -ne 'FileStorage'
        $hasFile = $kind -in 'StorageV2', 'Storage', 'FileStorage'
        $find = {
            param([string] $Severity, [string] $Signal, [string] $Title, [string] $Detail, [string] $Fix)
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.StorageAccountFinding'; Severity = $Severity; Account = $name; Signal = $Signal; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceGroup = [string]$s['resourceGroup']; Subscription = & $subName ([string]$s['subscriptionId']); ResourceId = $id })
        }

        # --- Health: the workbook's Overview tab ------------------------------------------------------------------
        $core = & $call $Metric $id 'Core'
        $metricsRead = [bool]($core -and -not $core.Error)
        $transactions = [long](& $sum (& $pointsOf $core 'Transactions') 'total')
        $availability = & $round (& $mean (& $values (& $pointsOf $core 'Availability') 'average')) 3
        $e2e = & $round (& $mean (& $values (& $pointsOf $core 'SuccessE2ELatency') 'average'))
        $server = & $round (& $mean (& $values (& $pointsOf $core 'SuccessServerLatency') 'average'))
        $client = if ($null -ne $e2e -and $null -ne $server) { & $round ([Math]::Max(0, $e2e - $server)) } else { $null }
        $ingress = & $gb (& $sum (& $pointsOf $core 'Ingress') 'total')
        $egress = & $gb (& $sum (& $pointsOf $core 'Egress') 'total')
        $byType = @{}
        $buckets = @{ Success = 0.0; Throttling = 0.0; Server = 0.0; Authorization = 0.0; Network = 0.0; Client = 0.0 }
        $responses = & $call $Metric $id 'Responses'
        foreach ($series in @(if ($responses -and -not $responses.Error) { $responses.Series })) {
            $type = [string]$series.Dims['responsetype']
            $n = & $sum $series.Points 'total'
            if (-not $n) { continue }
            $byType[$type] = $n + $(if ($byType.Contains($type)) { $byType[$type] } else { 0 })
            $bucket = switch -Regex ($type) {
                'Success$' { 'Success'; break }
                'Throttling|ServerBusy' { 'Throttling'; break }
                '^Server' { 'Server'; break }
                'Authoriz|Authentic' { 'Authorization'; break }
                'Network|ClientTimeout' { 'Network'; break }
                default { 'Client' }
            }
            $buckets[$bucket] += $n
        }
        foreach ($k in $buckets.Keys) { $label = if ($k -eq 'Client') { 'Client (404, 409...)' } else { $k }; $responseTotals[$label] += $buckets[$k] }
        $failed = $buckets.Throttling + $buckets.Server + $buckets.Authorization + $buckets.Network
        $errorRate = if ($transactions) { & $round (100.0 * $failed / $transactions) 2 } else { $null }
        $rateOf = { param([double] $N) if ($transactions) { 100.0 * $N / $transactions } else { 0 } }

        # --- Capacity: the workbook's Capacity tab (the latest value) ---------------------------------------------
        $cap = & $call $Capacity $id 'Capacity'
        $blobCap = & $call $Capacity "$id/blobServices/default" 'Capacity'
        $fileCap = & $call $Capacity "$id/fileServices/default" 'Capacity'
        $queueCap = & $call $Capacity "$id/queueServices/default" 'Capacity'
        $tableCap = & $call $Capacity "$id/tableServices/default" 'Capacity'
        $usedGb = & $gb (& $latest (& $pointsOf $cap 'UsedCapacity'))
        $blobGb = & $gb (& $latest (& $pointsOf $blobCap 'BlobCapacity'))
        $count = { param($Answer, [string] $Name) $v = & $latest (& $pointsOf $Answer $Name); if ($null -eq $v) { $null } else { [long]$v } }

        # --- Posture --------------------------------------------------------------------------------------------
        $sku = [string]$s['sku']
        $redundancy = if ($sku -match '_(.+)$') { $Matches[1] } else { $sku }
        $httpsOnly = [string](& $at $p 'supportsHttpsTrafficOnly') -ne 'False'
        $tls = [string](& $at $p 'minimumTlsVersion')
        $anonymous = [string](& $at $p 'allowBlobPublicAccess') -eq 'True'
        $sharedKey = [string](& $at $p 'allowSharedKeyAccess') -ne 'False'
        $network = if ([string](& $at $p 'publicNetworkAccess') -eq 'Disabled') { 'Private' } elseif ([string](& $at $p 'networkAcls', 'defaultAction') -eq 'Deny') { 'Firewall' } else { 'Public' }
        $endpoints = @(@(& $at $p 'privateEndpointConnections') | Where-Object { [string](& $at $_ 'properties', 'privateLinkServiceConnectionState', 'status') -eq 'Approved' }).Count
        $crossTenant = [string](& $at $p 'allowCrossTenantReplication') -eq 'True'
        $cmk = [string](& $at $p 'encryption', 'keySource') -eq 'Microsoft.Keyvault'
        $keyDates = @(foreach ($k in 'key1', 'key2') { $d = & $at $p 'keyCreationTime', $k; if ($d) { try { ([datetime]$d).ToUniversalTime() } catch { $null } } }) | Where-Object { $_ }
        $keyAge = if ($sharedKey -and @($keyDates).Count) { [int][Math]::Floor(($Now - (@($keyDates) | Sort-Object | Select-Object -First 1)).TotalDays) } else { $null }
        $keyPolicy = & $at $p 'keyPolicy', 'keyExpirationPeriodInDays'
        $sasPolicy = [string](& $at $p 'sasPolicy', 'sasExpirationPeriod')
        $plan = [string]$defender[[string]$s['subscriptionId']]
        $tier = [string]$s['accessTier']

        # --- Data protection and logs ---------------------------------------------------------------------------
        $set = if ($Setting.Contains($id)) { $Setting[$id] } else { @{ Blob = $null; File = $null; Lifecycle = $null; Logs = $null } }
        $blob = if (& $ok $set.Blob) { & $at $set.Blob 'Body', 'properties' } else { $null }
        $blobRead = $null -ne $blob
        $retention = { param($Policy) if ([string](& $at $Policy 'enabled') -eq 'True') { [int](& $at $Policy 'days') } else { 0 } }
        $blobSoft = if ($blobRead) { & $retention (& $at $blob 'deleteRetentionPolicy') } else { $null }
        $containerSoft = if ($blobRead) { & $retention (& $at $blob 'containerDeleteRetentionPolicy') } else { $null }
        $versioning = if ($blobRead) { [string](& $at $blob 'isVersioningEnabled') -eq 'True' } else { $null }
        $changeFeed = if ($blobRead) { [string](& $at $blob 'changeFeed', 'enabled') -eq 'True' } else { $null }
        $pitr = if ($blobRead) { [string](& $at $blob 'restorePolicy', 'enabled') -eq 'True' } else { $null }
        $shareSoft = if (& $ok $set.File) { & $retention (& $at $set.File 'Body', 'properties', 'shareDeleteRetentionPolicy') } else { $null }
        $lifecycle = if (& $ok $set.Lifecycle) { @(& $at $set.Lifecycle 'Body', 'properties', 'policy', 'rules').Count } elseif ($set.Lifecycle -and $set.Lifecycle['Status'] -eq 404) { 0 } else { $null }
        $logsTo = $null
        foreach ($diagnostic in @(if ($set.Logs -and -not $set.Logs['Error']) { & $at $set.Logs 'Items' })) {
            $sp = & $at $diagnostic 'properties'
            $workspace = ([string](& $at $sp 'workspaceId')).ToLowerInvariant()
            if (-not $workspace) { continue }
            $on = @(@(& $at $sp 'logs') | Where-Object { (& $at $_ 'enabled') -eq $true -and ([string](& $at $_ 'category') -in 'StorageRead', 'StorageWrite', 'StorageDelete' -or [string](& $at $_ 'categoryGroup') -in 'audit', 'allLogs') }).Count
            if ($on) { $logsTo = $workspace; break }
        }
        $logsRead = [bool]($set.Logs -and -not $set.Logs['Error'])

        # --- Findings: health -------------------------------------------------------------------------------------
        if ($metricsRead -and $transactions -gt 0 -and $null -ne $availability -and $availability -lt 99.9) { & $find 'High' 'Availability' 'Availability below 99.9%' "Average availability $availability% over the period." 'Check Resource Health and the failing requests by response type; retry transient failures with exponential backoff in the clients.' }
        if ($buckets.Throttling -gt 0) { $r = & $rateOf $buckets.Throttling; & $find $(if ($r -ge 1 -or $buckets.Throttling -ge 100) { 'High' } else { 'Medium' }) 'Throttling' 'Requests throttled' ('{0:N0} request(s) throttled ({1:N2}% of transactions): the account, a partition or a share hit its scalability limit.' -f $buckets.Throttling, $r) 'Retry with exponential backoff, spread hot partitions (avoid sequential blob names and single table partitions), and split the load across accounts - or use premium storage for high IOPS.' }
        if ($buckets.Server -gt 0 -and (& $rateOf $buckets.Server) -ge 0.1) { & $find 'Medium' 'Errors' 'Server errors and timeouts' ('{0:N0} request(s) failed on the service side (ServerTimeout, ServerOther).' -f $buckets.Server) 'Retry with backoff, and check Resource Health and Azure status for the region; persistent server timeouts often mean requests that are too large or too slow.' }
        if ($buckets.Authorization -gt 0) { & $find $(if ((& $rateOf $buckets.Authorization) -ge 1) { 'High' } else { 'Medium' }) 'Errors' 'Authorization or authentication failures' ('{0:N0} request(s) refused: expired SAS tokens, wrong keys, or identities without a data role.' -f $buckets.Authorization) 'Turn on the blob logs and find the caller (StorageBlobLogs, StatusCode 403); fix its SAS expiry, key or RBAC data role.' }
        if ($buckets.Network -gt 0 -and (& $rateOf $buckets.Network) -ge 1) { & $find 'Low' 'Errors' 'Network errors and client timeouts' ('{0:N0} request(s) ended with a network error or client timeout.' -f $buckets.Network) 'Check the client''s network path and timeouts; large transfers need longer client timeouts or parallel, chunked uploads.' }
        if ($null -ne $server -and $server -ge 100) { & $find 'Medium' 'Latency' 'Slow server responses' "Server latency averaged $server ms (end to end $e2e ms)." 'Look for large objects, hot partitions or throttling; premium (SSD) accounts serve small, frequent requests much faster.' }
        if ($null -ne $client -and $client -ge 100 -and $e2e -ge 150) { & $find 'Low' 'Latency' 'Time lost between the client and storage' "End-to-end latency averaged $e2e ms, of which $client ms is outside the service (server $server ms)." 'The client or its network is the bottleneck: keep clients in the same region, check bandwidth, CPU and connection limits on the client.' }

        # --- Findings: security ---------------------------------------------------------------------------------
        if (-not $httpsOnly) { & $find 'High' 'Security' 'HTTP allowed' 'Secure transfer isn''t required: data can travel unencrypted.' 'Require secure transfer (HTTPS only).' }
        if ($tls -notin 'TLS1_2', 'TLS1_3') { & $find 'High' 'Security' 'TLS below 1.2 accepted' "Minimum TLS version: $(if ($tls) { $tls } else { 'not set (TLS 1.0)' })." 'Set the minimum TLS version to 1.2 (TLS 1.0 and 1.1 are retired for Azure Storage).' }
        if ($anonymous) { & $find 'High' 'Security' 'Anonymous blob access allowed' 'Containers can be made public, readable by anyone with the URL.' 'Turn off anonymous (public) blob access; serve public content through Azure Front Door or CDN with private origins.' }
        if ($network -eq 'Public' -and -not $endpoints) { & $find 'High' 'Security' 'Open to every network' 'Public network access is on, with no firewall rules and no private endpoint.' 'Disable public network access and use private endpoints, or deny by default and allow only the networks that need it.' }
        if ($sharedKey) { & $find 'Medium' 'Security' 'Shared key access allowed' 'The account keys - and SAS tokens signed with them - grant full access and can''t be scoped or audited per user.' 'Use Microsoft Entra ID (RBAC data roles) and user delegation SAS, then turn off shared key access.' }
        if ($null -ne $keyAge -and $keyAge -gt 90) { & $find 'Medium' 'Security' 'Account keys not rotated in 90+ days' "The older key is $keyAge days old." 'Rotate the keys (one at a time), store them in Key Vault, and set a key expiration policy - or turn shared keys off.' }
        if ($sharedKey -and $null -eq $keyPolicy) { & $find 'Low' 'Security' 'No key expiration policy' 'Nothing reminds you to rotate the account keys.' 'Set a key expiration policy (for example 90 days) so Azure Policy and Advisor flag stale keys.' }
        if ($sharedKey -and -not $sasPolicy) { & $find 'Low' 'Security' 'No SAS expiration policy' 'Service SAS tokens can be issued with any lifetime.' 'Set a SAS expiration policy (for example one day), so long-lived tokens are flagged.' }
        if ($crossTenant) { & $find 'Medium' 'Security' 'Cross-tenant replication allowed' 'Object replication can copy data to an account in another Microsoft Entra tenant.' 'Turn off cross-tenant replication unless you need it.' }
        if ($hasBlob -and $logsRead -and -not $logsTo) { & $find 'Medium' 'Security' 'No blob logs to Log Analytics' 'StorageRead, StorageWrite and StorageDelete aren''t sent to a workspace: who read or deleted data can''t be investigated.' 'Add a diagnostic setting on the blob service sending the audit category group (or StorageRead, StorageWrite and StorageDelete) to a Log Analytics workspace.' }
        if ($plan -ne 'Standard') { & $find 'Low' 'Security' 'Defender for Storage off' 'Malware uploads, unusual access and data exfiltration raise no alert.' 'Turn on Microsoft Defender for Storage for the subscription (with malware scanning for accounts that receive uploads).' }
        if ($alerts.Contains($id)) { & $find 'High' 'Security' 'Defender alerts in the last 30 days' "$($alerts[$id]) alert(s) on this account." 'Investigate them in Defender for Cloud > Security alerts.' }

        # --- Findings: data protection and reliability ------------------------------------------------------------
        if ($sku -match '_LRS$') { & $find 'Medium' 'Protection' 'Locally redundant only (LRS)' 'All copies are in one datacentre: a zone outage makes the data unavailable.' 'Move to ZRS (zone outages) or GZRS / RA-GZRS (region outages) for production data.' }
        if ($blobRead -and $blobSoft -eq 0) { & $find 'Medium' 'Protection' 'Blob soft delete off' 'A deleted or overwritten blob can''t be recovered.' 'Turn on blob soft delete (7 days or more).' }
        elseif ($blobRead -and $blobSoft -lt 7) { & $find 'Low' 'Protection' 'Blob soft delete under 7 days' "Deleted blobs are kept $blobSoft day(s)." 'Keep deleted blobs at least 7 days, so a mistake found after a weekend can still be undone.' }
        if ($blobRead -and $containerSoft -eq 0) { & $find 'Medium' 'Protection' 'Container soft delete off' 'A deleted container - and every blob in it - can''t be recovered.' 'Turn on container soft delete (7 days or more).' }
        if ($blobRead -and -not $versioning -and $kind -ne 'Storage') { & $find 'Low' 'Protection' 'Blob versioning off' 'An overwritten blob''s previous content is lost.' 'Turn on blob versioning (with a lifecycle rule to delete old versions).' }
        if ($hasFile -and $null -ne $shareSoft -and $shareSoft -eq 0) { & $find 'Medium' 'Protection' 'File share soft delete off' 'A deleted file share can''t be recovered.' 'Turn on file share soft delete (7 days or more).' }

        # --- Findings: cost and usage ---------------------------------------------------------------------------
        if ($kind -eq 'Storage') { & $find 'Medium' 'Cost' 'General-purpose v1 account' 'Classic (v1) accounts lack access tiers, lifecycle management and many security features, and some prices are higher.' 'Upgrade to general-purpose v2 (in place, no downtime).' }
        if ($kind -eq 'BlobStorage') { & $find 'Low' 'Cost' 'Legacy Blob storage account' 'BlobStorage accounts are a legacy kind.' 'Upgrade to general-purpose v2.' }
        if ($hasBlob -and $lifecycle -eq 0 -and ($null -eq $blobGb -or $blobGb -ge 1)) { & $find 'Low' 'Cost' 'No lifecycle management' "No lifecycle rules$(if ($blobGb) { " for $blobGb GB of blobs" })." 'Add lifecycle rules: move data to cool, cold or archive as it ages, and delete old versions, snapshots and temporary data.' }
        if ($metricsRead -and $transactions -eq 0) { & $find 'Low' 'Cost' 'No transactions in the period' 'Nothing read or wrote the account: it may be unused.' 'Confirm it is still needed; delete it, or move its data to a cheaper tier.' }
        elseif ($tier -eq 'Hot' -and $null -ne $blobGb -and $blobGb -ge 100 -and $transactions / $days -lt 1000) { & $find 'Low' 'Cost' 'Hot tier with little activity' ('{0:N0} GB of blobs in the hot tier, but only about {1:N0} transactions a day.' -f $blobGb, ($transactions / $days)) 'Set the default access tier to cool (or use lifecycle rules) - data read rarely costs much less to store there.' }

        # --- Heat map: each signal 0-100 ------------------------------------------------------------------------
        $cell = { param($Score) if ($null -eq $Score) { $null } else { @{ Score = [Math]::Round([Math]::Max(0, [Math]::Min(100, [double]$Score)), 1) } } }
        $securityChecks = @($httpsOnly, ($tls -in 'TLS1_2', 'TLS1_3'), (-not $anonymous), ($network -ne 'Public' -or $endpoints -gt 0), (-not $sharedKey), (-not $crossTenant), ($plan -eq 'Standard'))
        if ($hasBlob -and $logsRead) { $securityChecks += [bool]$logsTo }
        $protectionChecks = @($sku -notmatch '_LRS$')
        if ($blobRead) { $protectionChecks += @(($blobSoft -ge 7), ($containerSoft -gt 0)); if ($kind -ne 'Storage') { $protectionChecks += [bool]$versioning } }
        if ($hasFile -and $null -ne $shareSoft) { $protectionChecks += ($shareSoft -gt 0) }
        $costChecks = @(($kind -notin 'Storage', 'BlobStorage'), (-not ($metricsRead -and $transactions -eq 0)))
        if ($hasBlob -and $null -ne $lifecycle) { $costChecks += ($lifecycle -gt 0 -or ($null -ne $blobGb -and $blobGb -lt 1)) }
        $share = { param([object[]] $Checks) 100.0 * @($Checks | Where-Object { $_ }).Count / [Math]::Max(1, $Checks.Count) }
        $scores = [ordered]@{
            Availability = $(if ($metricsRead -and $transactions -gt 0 -and $null -ne $availability) { ($availability - 99) * 100 } else { $null })
            Errors       = $(if ($transactions) { 100 - (& $rateOf ($buckets.Server + $buckets.Authorization + $buckets.Network)) * 10 } else { $null })
            Throttling   = $(if ($transactions) { 100 - (& $rateOf $buckets.Throttling) * 20 } else { $null })
            Latency      = $(if ($null -ne $e2e) { 100 - [Math]::Max(0, $e2e - 50) / 3 } else { $null })
            Security     = & $share $securityChecks
            Protection   = & $share $protectionChecks
            Cost         = & $share $costChecks
        }
        $cells = @(foreach ($signal in $signals) { & $cell $scores[$signal] })
        $scored = @($cells | Where-Object { $_ })
        $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1) } else { $null }
        $heatRows.Add(@{ Label = $name; Filter = $name; Cells = $cells; Total = $(if ($null -ne $overall) { @{ Score = $overall } } else { $null }); Overall = $overall })

        $accountRows.Add([pscustomobject][ordered]@{
                PSTypeName              = 'AAC.StorageAccountAssessment'
                Account                 = $name
                Score                   = $overall
                Availability            = $availability
                Transactions            = $transactions
                Successes               = [long]$buckets.Success
                Throttled               = [long]$buckets.Throttling
                ServerErrors            = [long]$buckets.Server
                AuthErrors              = [long]$buckets.Authorization
                NetworkErrors           = [long]$buckets.Network
                ClientErrors            = [long]$buckets.Client
                ErrorRate               = $errorRate
                E2ELatencyMs            = $e2e
                ServerLatencyMs         = $server
                ClientLatencyMs         = $client
                IngressGB               = $ingress
                EgressGB                = $egress
                ResponseTypes           = (@($byType.GetEnumerator() | Where-Object { $_.Key -notmatch 'Success$' } | Sort-Object -Property Value -Descending | Select-Object -First 4 | ForEach-Object { '{0} {1:N0}' -f $_.Key, $_.Value }) -join ', ')
                UsedGB                  = $usedGb
                BlobGB                  = $blobGb
                FileGB                  = & $gb (& $latest (& $pointsOf $fileCap 'FileCapacity'))
                QueueGB                 = & $gb (& $latest (& $pointsOf $queueCap 'QueueCapacity'))
                TableGB                 = & $gb (& $latest (& $pointsOf $tableCap 'TableCapacity'))
                Blobs                   = & $count $blobCap 'BlobCount'
                Containers              = & $count $blobCap 'ContainerCount'
                FileShares              = & $count $fileCap 'FileShareCount'
                Kind                    = $kind
                Sku                     = $sku
                Redundancy              = $redundancy
                AccessTier              = $tier
                HttpsOnly               = $httpsOnly
                MinTls                  = $tls
                BlobAnonymousAccess     = $anonymous
                SharedKeyAccess         = $sharedKey
                Network                 = $network
                PrivateEndpoints        = $endpoints
                CrossTenantReplication  = $crossTenant
                Encryption              = $(if ($cmk) { 'Customer-managed key' } else { 'Microsoft-managed key' })
                KeyAgeDays              = $keyAge
                KeyExpiryPolicy         = $(if ($null -ne $keyPolicy) { "$keyPolicy days" } else { '' })
                SasExpiryPolicy         = $sasPolicy
                Defender                = $(if ($plan -eq 'Standard') { 'On' } elseif ($plan) { 'Off' } else { 'Unknown' })
                LogsTo                  = $(if ($logsTo) { if ($WorkspaceName.Contains($logsTo)) { $WorkspaceName[$logsTo] } else { ($logsTo -split '/')[-1] } } else { '' })
                BlobSoftDeleteDays      = $blobSoft
                ContainerSoftDeleteDays = $containerSoft
                Versioning              = $versioning
                ChangeFeed              = $changeFeed
                PointInTimeRestore      = $pitr
                ShareSoftDeleteDays     = $shareSoft
                LifecycleRules          = $lifecycle
                HierarchicalNamespace   = [string](& $at $p 'isHnsEnabled') -eq 'True'
                MetricsError            = $(if ($core -and $core.Error) { [string]$core.Error } else { '' })
                Findings                = @($findings | Where-Object { $_.ResourceId -eq $id }).Count
                Location                = [string]$s['location']
                ResourceGroup           = [string]$s['resourceGroup']
                Subscription            = & $subName ([string]$s['subscriptionId'])
                ResourceId              = $id
            })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $worst = @($heatRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.Overall) { 101 } else { $_.Overall } } }, Label | Select-Object -First 40)
    $usedTotal = 0.0; $transactionTotal = [long]0
    foreach ($a in $accountRows) { if ($null -ne $a.UsedGB) { $usedTotal += $a.UsedGB }; $transactionTotal += $a.Transactions }
    @{
        Accounts      = $accountRows.ToArray()
        Findings      = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Account, Finding)
        HeatMap       = @{ Title = 'Storage accounts by signal'; RowHeader = 'Account'; Columns = $signals; Rows = $worst; Table = 'findings'; RowKey = 'Account'; ColumnKey = 'Signal'; ConsoleColumns = 7
            Note = "0-100 per signal, worst accounts first$(if ($heatRows.Count -gt 40) { " (40 of $($heatRows.Count))" }): availability, errors, throttling, latency, security, data protection, cost. Click a cell for its findings." }
        ResponseTypes = $responseTotals
        Stats         = @{
            Accounts     = $accountRows.Count
            Transactions = $transactionTotal
            Throttled    = [long]$responseTotals['Throttling']
            Failed       = [long]($responseTotals['Throttling'] + $responseTotals['Server'] + $responseTotals['Authorization'] + $responseTotals['Network'])
            UsedTB       = [Math]::Round($usedTotal / 1024, 2)
            Public       = @($accountRows | Where-Object { $_.Network -eq 'Public' -and -not $_.PrivateEndpoints }).Count
            Anonymous    = @($accountRows | Where-Object BlobAnonymousAccess).Count
            NoSoftDelete = @($accountRows | Where-Object { $_.BlobSoftDeleteDays -eq 0 }).Count
            Lrs          = @($accountRows | Where-Object { $_.Sku -match '_LRS$' }).Count
            Idle         = @($accountRows | Where-Object { $_.Transactions -eq 0 -and -not $_.MetricsError }).Count
            High         = @($findings | Where-Object Severity -EQ 'High').Count
        }
    }
}
