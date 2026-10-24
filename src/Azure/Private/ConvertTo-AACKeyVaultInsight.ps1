function ConvertTo-AACKeyVaultInsight {
    <#
    .SYNOPSIS
        Turns what Get-AACKeyVaultInsight read into per-vault health, posture,
        operations, objects, findings and a heat map.
    .DESCRIPTION
        No Azure calls. Per vault (AAC.KeyVaultInsight):
          health     Availability (average %), Transactions, Successes (2xx),
                     Unauthorized (401 - includes the SDKs' normal challenge),
                     Forbidden (403), Throttled (429), OtherFailures,
                     FailureRate (% of transactions: 403, 429 and other
                     failures), LatencyAvgMs, LatencyMaxMs, SaturationAvg and
                     SaturationMax (%), RequestTypes
          posture    SoftDelete, PurgeProtection, PermissionModel (RBAC or
                     Access policies), Network (Private, Firewall, Public),
                     PrivateEndpoints, Defender, AuditLogsTo (the workspace,
                     or empty) and AuditTable
          objects    Secrets, Keys, Certificates, Expired, Expiring, NoExpiry,
                     ObjectAccess (with -Object)
        Findings (AAC.KeyVaultFinding: Severity, Vault, Signal, Finding,
        Detail, Recommendation) - Signal is the heat map's column:
        Availability, Failures, Throttling, Saturation, Posture, Objects,
        Usage. The heat map scores each vault 0-100 per signal.
        Returns @{ Vaults; Operations; Objects; Findings; HeatMap; StatusCodes;
        RequestTypes; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Vault,

        # Read-AACKeyVaultTelemetry's result.
        [hashtable] $Telemetry = @{},

        [AllowEmptyCollection()]
        [object[]] $Pricing = @(),

        [AllowEmptyCollection()]
        [object[]] $Alert = @(),

        # Workspace resource ID (lower case) -> name.
        [hashtable] $WorkspaceName = @{},

        # Read-AACKeyVaultLog's rows, or $null when not read.
        [AllowNull()]
        [object[]] $Log,

        # Read-AACKeyVaultObject's result, or $null when not read.
        [AllowNull()]
        [hashtable] $Object,

        [hashtable] $SubscriptionName = @{},

        [int] $ExpiryDays = 30,

        [datetime] $Now = [datetime]::UtcNow
    )

    $at = { param($Row, [string[]] $Keys) Get-AACMember -InputObject $Row -Key $Keys }
    # A metric answer's series: @(@{ Name; Dimension; Points }).
    $series = {
        param($Answer)
        if (-not $Answer -or (& $at $Answer 'Error') -or -not (& $at $Answer 'Body')) { return }
        foreach ($m in @(& $at $Answer 'Body', 'value')) {
            foreach ($ts in @(& $at $m 'timeseries')) {
                $dimension = @(@(& $at $ts 'metadatavalues') | ForEach-Object { [string](& $at $_ 'value') }) -join '/'
                @{ Name = [string](& $at $m 'name', 'value'); Dimension = $dimension; Points = @(& $at $ts 'data' | Where-Object { $null -ne $_ }) }
            }
        }
    }
    $sum = { param([object[]] $Points, [string] $Field) $t = 0.0; foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { $t += [double]$v } }; $t }
    $values = { param([object[]] $Points, [string] $Field) @(foreach ($p in $Points) { $v = & $at $p $Field; if ($null -ne $v) { [double]$v } }) }
    $mean = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Average).Average } else { $null } }
    $peak = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Maximum).Maximum } else { $null } }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $defender = @{}
    foreach ($p in $Pricing) { $defender[[string]$p['subscriptionId']] = [string]$p['tier'] }
    $alerts = @{}
    foreach ($a in $Alert) { $id = [string]$a['resourceId']; $alerts[$id] = 1 + $(if ($alerts.Contains($id)) { $alerts[$id] } else { 0 }) }

    $findings = [System.Collections.Generic.List[object]]::new()
    $statusTotals = @{ '2xx' = 0.0; '401' = 0.0; '403' = 0.0; '429' = 0.0; 'Other' = 0.0 }
    $typeTotals = @{}
    $vaultRows = [System.Collections.Generic.List[object]]::new()
    $objectRows = [System.Collections.Generic.List[object]]::new()
    $heatRows = [System.Collections.Generic.List[object]]::new()
    $signals = @('Availability', 'Failures', 'Throttling', 'Saturation', 'Posture', 'Objects')

    foreach ($v in @($Vault | Sort-Object -Property { [string]$_['name'] })) {
        $id = [string]$v['id']
        $name = [string]$v['name']
        $p = $v['properties']
        $t = if ($Telemetry.Contains($id)) { $Telemetry[$id] } else { @{ Core = $null; Results = $null; Types = $null; Settings = $null } }
        $find = {
            param([string] $Severity, [string] $Signal, [string] $Title, [string] $Detail, [string] $Fix)
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.KeyVaultFinding'; Severity = $Severity; Vault = $name; Signal = $Signal; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceGroup = [string]$v['resourceGroup']; Subscription = & $subName ([string]$v['subscriptionId']); ResourceId = $id })
        }

        # --- Health: the workbook's Overview and Failures tabs, and saturation ----------------------------------
        $core = @{}
        foreach ($s in @(& $series $t.Core)) { $core[$s.Name] = $s.Points }
        $pointsOf = { param([string] $Metric) if ($core.Contains($Metric)) { @($core[$Metric]) } else { @() } }
        $availability = & $round (& $mean (& $values (& $pointsOf 'Availability') 'average')) 3
        $transactions = [int](& $sum (& $pointsOf 'ServiceApiHit') 'total')
        $latencyAvg = & $round (& $mean (& $values (& $pointsOf 'ServiceApiLatency') 'average'))
        $latencyMax = & $round (& $peak (& $values (& $pointsOf 'ServiceApiLatency') 'maximum'))
        $saturationAvg = & $round (& $mean (& $values (& $pointsOf 'SaturationShoebox') 'average'))
        $saturationMax = & $round (& $peak (& $values (& $pointsOf 'SaturationShoebox') 'maximum'))
        $codes = @{ '2xx' = 0.0; '401' = 0.0; '403' = 0.0; '429' = 0.0; 'Other' = 0.0 }
        foreach ($s in @(& $series $t.Results)) {
            $n = & $sum $s.Points 'total'
            $bucket = if ($s.Dimension -match '^2\d\d$') { '2xx' } elseif ($s.Dimension -in '401', '403', '429') { $s.Dimension } else { 'Other' }
            $codes[$bucket] += $n; $statusTotals[$bucket] += $n
        }
        $types = @{}
        foreach ($s in @(& $series $t.Types)) { $n = & $sum $s.Points 'total'; if ($n) { $types[$s.Dimension] = $n; $typeTotals[$s.Dimension] = $n + $(if ($typeTotals.Contains($s.Dimension)) { $typeTotals[$s.Dimension] } else { 0 }) } }
        $failed = $codes['403'] + $codes['429'] + $codes['Other']
        $failureRate = if ($transactions) { & $round (100.0 * $failed / $transactions) 2 } else { $null }
        $throttleRate = if ($transactions) { 100.0 * $codes['429'] / $transactions } else { 0 }
        $metricsRead = [bool]($t.Core -and -not (& $at $t.Core 'Error'))

        # --- Posture ---------------------------------------------------------------------------------------------
        $softDelete = [string](& $at $p 'enableSoftDelete') -ne 'False'
        $purge = [string](& $at $p 'enablePurgeProtection') -eq 'True'
        $rbac = [string](& $at $p 'enableRbacAuthorization') -eq 'True'
        $network = if ([string](& $at $p 'publicNetworkAccess') -eq 'Disabled') { 'Private' } elseif ([string](& $at $p 'networkAcls', 'defaultAction') -eq 'Deny') { 'Firewall' } else { 'Public' }
        $endpoints = @(@(& $at $p 'privateEndpointConnections') | Where-Object { [string](& $at $_ 'properties', 'privateLinkServiceConnectionState', 'status') -eq 'Approved' }).Count
        $plan = [string]$defender[[string]$v['subscriptionId']]
        $audit = $null
        foreach ($setting in @(if ($t.Settings -and -not (& $at $t.Settings 'Error')) { & $at $t.Settings 'Items' })) {
            $sp = & $at $setting 'properties'
            $workspace = ([string](& $at $sp 'workspaceId')).ToLowerInvariant()
            if (-not $workspace) { continue }
            $on = @(@(& $at $sp 'logs') | Where-Object { (& $at $_ 'enabled') -eq $true -and ([string](& $at $_ 'category') -eq 'AuditEvent' -or [string](& $at $_ 'categoryGroup') -in 'audit', 'allLogs') }).Count
            if ($on) { $audit = @{ Workspace = $workspace; Table = $(if ([string](& $at $sp 'logAnalyticsDestinationType') -eq 'Dedicated') { 'AZKVAuditLogs' } else { 'AzureDiagnostics' }) }; break }
        }
        $postureChecks = @($softDelete, $purge, $rbac, ($network -ne 'Public' -or $endpoints -gt 0), [bool]$audit, ($plan -eq 'Standard'))

        # --- Objects ---------------------------------------------------------------------------------------------
        $mine = @(if ($Object) { $Object.Items | Where-Object { $_.VaultId -eq $id } })
        $access = if ($Object) { [string]$Object.Access[$id] } else { '' }
        foreach ($o in $mine) {
            $days = if ($o.Expires) { [Math]::Floor(($o.Expires - $Now).TotalDays) } else { $null }
            $status = if (-not $o.Enabled) { 'Disabled' } elseif ($null -eq $o.Expires) { 'No expiry' } elseif ($o.Expires -lt $Now) { 'Expired' } elseif ($days -le $ExpiryDays) { 'Expiring' } else { 'OK' }
            $objectRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.KeyVaultObject'; Vault = $name; Kind = $o.Kind; Name = $o.Name; Enabled = $o.Enabled; Expires = $o.Expires; DaysLeft = $days; Status = $status; ResourceGroup = [string]$v['resourceGroup']; Subscription = & $subName ([string]$v['subscriptionId']); ResourceId = $id })
        }
        $countOf = { param([string] $S) @($objectRows | Where-Object { $_.ResourceId -eq $id -and $_.Status -eq $S }).Count }
        $expired = & $countOf 'Expired'; $expiring = & $countOf 'Expiring'; $noExpiry = & $countOf 'No expiry'

        # --- Findings --------------------------------------------------------------------------------------------
        if (-not $softDelete) { & $find 'High' 'Posture' 'Soft delete off' 'A deleted vault, key or secret can''t be recovered.' 'Turn soft delete on (it can''t be turned off again).' }
        if (-not $purge) { & $find 'High' 'Posture' 'Purge protection off' 'Anyone with the right role can purge deleted keys and secrets before the retention period ends.' 'Turn on purge protection.' }
        if ($network -eq 'Public' -and -not $endpoints) { & $find 'High' 'Posture' 'Open to every network' 'Public network access is on, with no firewall rules and no private endpoint.' 'Disable public access and use a private endpoint, or deny by default and allow only the networks that need it.' }
        if (-not $rbac) { & $find 'Medium' 'Posture' 'Access policies, not RBAC' 'Access policies are vault-wide and can''t be scoped, audited or managed with PIM like Azure RBAC.' 'Migrate to the Azure RBAC permission model.' }
        if (-not $audit) { & $find 'Medium' 'Posture' 'No audit logs to Log Analytics' 'AuditEvent isn''t sent to a workspace: who did what can''t be investigated (the workbook''s Operations tab stays empty).' 'Add a diagnostic setting sending the audit category group to a Log Analytics workspace (resource-specific table).' }
        if ($plan -ne 'Standard') { & $find 'Low' 'Posture' 'Defender for Key Vault off' 'Unusual access, such as from a Tor exit node or an unfamiliar app, raises no alert.' 'Turn on Microsoft Defender for Key Vault for the subscription.' }
        if ($alerts.Contains($id)) { & $find 'High' 'Posture' 'Defender alerts in the last 30 days' "$($alerts[$id]) alert(s) on this vault." 'Investigate them in Defender for Cloud > Security alerts.' }
        if ($metricsRead -and $transactions -gt 0 -and $null -ne $availability -and $availability -lt 99.9) { & $find 'High' 'Availability' 'Availability below 99.9%' "Average availability $availability% over the period." 'Check Resource Health and the failing requests; retry transient failures with backoff in the clients.' }
        if ($codes['429'] -gt 0) { & $find $(if ($throttleRate -ge 1 -or $codes['429'] -ge 100) { 'High' } else { 'Medium' }) 'Throttling' 'Requests throttled (429)' ('{0:N0} throttled request(s), {1:N2}% of transactions.' -f $codes['429'], $throttleRate) 'Cache secrets in the application (don''t read them per request), spread load over vaults, and retry with exponential backoff.' }
        if ($null -ne $saturationMax -and $saturationMax -ge 50) { & $find $(if ($saturationMax -ge 75) { 'High' } else { 'Medium' }) 'Saturation' 'Vault close to its limits' "Overall Vault Saturation peaked at $saturationMax% (average $saturationAvg%)." 'Reduce calls (cache, batch), or split the load across vaults before it throttles.' }
        if ($codes['403'] -gt 0) { & $find 'Medium' 'Failures' 'Requests denied (403)' ('{0:N0} request(s) refused for lack of permission.' -f $codes['403']) 'Find the caller (-IncludeOperations) and give its identity the role or access policy it needs - or stop the call.' }
        if ($codes['Other'] -gt 0 -and $transactions -and (100.0 * $codes['Other'] / $transactions) -ge 1) { & $find 'Medium' 'Failures' 'Other failed requests' ('{0:N0} request(s) failed (not 401, 403 or 429).' -f $codes['Other']) 'Look at the failing operations (-IncludeOperations): missing objects (404), bad requests (400) or service errors (5xx).' }
        if ($metricsRead -and $transactions -eq 0) { & $find 'Low' 'Usage' 'No transactions in the period' 'Nothing called the vault: it may be unused.' 'Confirm it is still needed; delete it (it is soft-deleted, so recoverable) or document why it is idle.' }
        if ($expired) { & $find 'High' 'Objects' 'Expired secrets, keys or certificates' "$expired object(s) have expired." 'Rotate or remove them; anything still using them is failing or about to.' }
        if ($expiring) { & $find 'Medium' 'Objects' "Expiring within $ExpiryDays days" "$expiring object(s) expire soon." 'Rotate them now, and set up rotation policies or Event Grid near-expiry notifications.' }
        if ($noExpiry) { & $find 'Low' 'Objects' 'Objects without an expiry date' "$noExpiry enabled object(s) never expire." 'Set expiry dates and rotation policies, so stale credentials don''t live forever.' }
        if ($access -in 'Not reachable', 'Denied') { & $find 'Info' 'Objects' "Objects not read: $($access.ToLowerInvariant())" $(if ($access -eq 'Denied') { 'Your account has no data-plane permission to list objects.' } else { 'The vault''s firewall or private endpoint blocks this machine.' }) $(if ($access -eq 'Denied') { 'Grant Key Vault Reader (RBAC) or a List access policy to read expiry dates.' } else { 'Run from a network the vault allows, or skip -IncludeObjects for it.' }) }

        # --- Heat map: each signal 0-100 ------------------------------------------------------------------------
        $cell = { param($Score) if ($null -eq $Score) { $null } else { @{ Score = [Math]::Round([Math]::Max(0, [Math]::Min(100, [double]$Score)), 1) } } }
        $scores = [ordered]@{
            Availability = $(if ($metricsRead -and $transactions -gt 0 -and $null -ne $availability) { ($availability - 99) * 100 } else { $null })
            Failures     = $(if ($transactions) { 100 - $failureRate * 10 } else { $null })
            Throttling   = $(if ($transactions) { 100 - $throttleRate * 20 } else { $null })
            Saturation   = $(if ($null -ne $saturationMax) { 100 - $saturationMax } else { $null })
            Posture      = 100.0 * @($postureChecks | Where-Object { $_ }).Count / $postureChecks.Count
            Objects      = $(if ($mine.Count) { 100.0 * @($objectRows | Where-Object { $_.ResourceId -eq $id -and $_.Status -in 'OK', 'Disabled' }).Count / $mine.Count } else { $null })
        }
        $cells = @(foreach ($s in $signals) { & $cell $scores[$s] })
        $scored = @($cells | Where-Object { $_ })
        $overall = if ($scored.Count) { [Math]::Round((@($scored | ForEach-Object { $_.Score }) | Measure-Object -Average).Average, 1) } else { $null }
        $heatRows.Add(@{ Label = $name; Filter = $name; Cells = $cells; Total = $(if ($null -ne $overall) { @{ Score = $overall } } else { $null }); Overall = $overall })

        $vaultRows.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.KeyVaultInsight'
                Vault            = $name
                Score            = $overall
                Availability     = $availability
                Transactions     = $transactions
                Successes        = [int]$codes['2xx']
                Unauthorized     = [int]$codes['401']
                Forbidden        = [int]$codes['403']
                Throttled        = [int]$codes['429']
                OtherFailures    = [int]$codes['Other']
                FailureRate      = $failureRate
                LatencyAvgMs     = $latencyAvg
                LatencyMaxMs     = $latencyMax
                SaturationAvg    = $saturationAvg
                SaturationMax    = $saturationMax
                RequestTypes     = (@($types.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 4 | ForEach-Object { '{0} {1:N0}' -f $_.Key, $_.Value }) -join ', ')
                Sku              = [string]$v['sku']
                SoftDelete       = $softDelete
                PurgeProtection  = $purge
                PermissionModel  = $(if ($rbac) { 'RBAC' } else { 'Access policies' })
                Network          = $network
                PrivateEndpoints = $endpoints
                Defender         = $(if ($plan -eq 'Standard') { 'On' } elseif ($plan) { 'Off' } else { 'Unknown' })
                AuditLogsTo      = $(if ($audit) { if ($WorkspaceName.Contains($audit.Workspace)) { $WorkspaceName[$audit.Workspace] } else { ($audit.Workspace -split '/')[-1] } } else { '' })
                AuditTable       = $(if ($audit) { $audit.Table } else { '' })
                AuditWorkspaceId = $(if ($audit) { $audit.Workspace } else { '' })
                Secrets          = @($mine | Where-Object Kind -EQ 'Secret').Count
                Keys             = @($mine | Where-Object Kind -EQ 'Key').Count
                Certificates     = @($mine | Where-Object Kind -EQ 'Certificate').Count
                Expired          = $expired
                Expiring         = $expiring
                NoExpiry         = $noExpiry
                ObjectAccess     = $access
                MetricsError     = $(if ($t.Core -and (& $at $t.Core 'Error')) { [string](& $at $t.Core 'Error') } else { '' })
                Findings         = @($findings | Where-Object { $_.ResourceId -eq $id }).Count
                Location         = [string]$v['location']
                ResourceGroup    = [string]$v['resourceGroup']
                Subscription     = & $subName ([string]$v['subscriptionId'])
                ResourceId       = $id
            })
    }

    # --- Operations (audit logs), by vault, operation and caller -------------------------------------------------
    $names = @{}
    foreach ($v in $vaultRows) { $names[$v.ResourceId] = $v.Vault }
    $operations = @(foreach ($r in @($Log | Where-Object { $null -ne $_ })) {
            $vid = [string]$r['VaultId']
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.KeyVaultOperation'; Vault = $(if ($names.Contains($vid)) { $names[$vid] } else { ($vid -split '/')[-1] }); Operation = [string]$r['Operation']
                Caller = [string]$r['Caller']; CallerIp = [string]$r['CallerIp']; Count = [int]$r['Count']; Failed = [int]$r['Failed']; AuthDenied = [int]$r['AuthDenied']; Throttled = [int]$r['Throttled']
                P99Ms = $(if ($null -ne $r['P99Ms']) { [Math]::Round([double]$r['P99Ms'], 1) } else { $null }); ResourceId = $vid
            }
        })
    foreach ($group in @($operations | Where-Object AuthDenied | Group-Object -Property ResourceId, Caller)) {
        $denied = ($group.Group | Measure-Object -Property AuthDenied -Sum).Sum
        if ($denied -lt 10) { continue }
        $first = $group.Group[0]
        $v = @($vaultRows | Where-Object ResourceId -EQ $first.ResourceId)[0]
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.KeyVaultFinding'; Severity = 'Medium'; Vault = $first.Vault; Signal = 'Failures'; Finding = 'A caller is repeatedly denied'
                Detail = "$('{0:N0}' -f $denied) denied request(s) from $(if ($first.Caller) { $first.Caller } else { 'an unknown caller' })$(if ($first.CallerIp) { " ($($first.CallerIp))" }): $(@($group.Group | ForEach-Object { $_.Operation } | Select-Object -Unique) -join ', ')."
                Recommendation = 'Give that identity the role it needs, or fix its configuration (wrong vault, expired credential, missing role assignment).'; ResourceGroup = $v.ResourceGroup; Subscription = $v.Subscription; ResourceId = $first.ResourceId })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $worst = @($heatRows | Sort-Object -Property @{ Expression = { if ($null -eq $_.Overall) { 101 } else { $_.Overall } } }, Label | Select-Object -First 40)
    @{
        Vaults       = $vaultRows.ToArray()
        Operations   = $operations
        Objects      = $objectRows.ToArray()
        Findings     = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Vault, Finding)
        HeatMap      = @{ Title = 'Vaults by signal'; RowHeader = 'Vault'; Columns = $signals; Rows = $worst; Table = 'findings'; RowKey = 'Vault'; ColumnKey = 'Signal'; ConsoleColumns = 6
            Note = "0-100 per signal, worst vaults first$(if ($heatRows.Count -gt 40) { " (40 of $($heatRows.Count))" }): availability, failures (403, 429, other), throttling, saturation, posture, objects. Click a cell for its findings." }
        StatusCodes  = $statusTotals
        RequestTypes = $typeTotals
        Stats        = @{
            Vaults      = $vaultRows.Count
            Transactions = [long](($vaultRows | Measure-Object -Property Transactions -Sum).Sum)
            Throttled   = [long]$statusTotals['429']
            Forbidden   = [long]$statusTotals['403']
            NoAuditLogs = @($vaultRows | Where-Object { -not $_.AuditLogsTo }).Count
            Saturated   = @($vaultRows | Where-Object { $_.SaturationMax -ge 75 }).Count
            Expired     = @($objectRows | Where-Object Status -EQ 'Expired').Count
            Expiring    = @($objectRows | Where-Object Status -EQ 'Expiring').Count
            High        = @($findings | Where-Object Severity -EQ 'High').Count
            Idle        = @($vaultRows | Where-Object { $_.Transactions -eq 0 -and -not $_.MetricsError }).Count
        }
    }
}
