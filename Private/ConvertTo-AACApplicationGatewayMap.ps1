function ConvertTo-AACApplicationGatewayMap {
    <#
    .SYNOPSIS
        Turns Application Gateways' configuration into the map's model (boxes,
        cards, lines), the traffic flows - listener to rule to path to backend
        settings to pool to targets - with their health, and findings.
    .DESCRIPTION
        No Azure calls. Boxes: subscription > resource group > virtual network
        > subnet > gateway (the gateway's own resource group when its network
        can't be read). Inside a gateway, cards in stages, left to right
        (ELK partitions): 0 frontend IPs and WAF policies, 1 listeners, 2
        rules, 3 path rules and redirects, 4 backend settings, 5 pools and
        probes, 6 targets. Lines: flow (traffic), probe, waf, redirect.

        Health, best first: the live check (-Health.Live: each target's state
        and the probe's reason), else metrics (healthy and unhealthy host
        counts per pool and setting). A pool or target is healthy, degraded
        (some unhealthy), unhealthy (none healthy) or unknown.

        Certificates' expiry comes from publicCertData (uploaded certificates,
        and Key Vault ones when Azure includes it): the leaf's NotAfter.

        Returns @{ Clusters; Nodes; Edges (as the map page reads them);
        Gateways (AAC.ApplicationGateway); Flows (AAC.ApplicationGatewayFlow);
        Findings (AAC.ApplicationGatewayFinding); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Gateway,

        # Rows read by ID (public IPs, WAF policies, networks, NICs).
        [AllowEmptyCollection()]
        [object[]] $Related = @(),

        # App Services whose host name is a pool target: @{ id; name; host; kind }.
        [AllowEmptyCollection()]
        [object[]] $Site = @(),

        [hashtable] $SubscriptionName = @{},

        # Read-AACApplicationGatewayHealth's result.
        [hashtable] $Health = @{ Metrics = @{}; Live = @{}; Errors = @{} },

        [int] $CertificateDays = 30,

        [datetime] $Now = [datetime]::UtcNow
    )

    $at = {
        param($Row, [string[]] $Keys)
        $value = $Row
        foreach ($key in $Keys) {
            if ($value -isnot [System.Collections.IDictionary]) { return $null }
            if ($value.Contains($key)) { $value = $value[$key]; continue }
            $found = $null
            foreach ($name in $value.Keys) { if ($name -eq $key) { $found = $value[$name]; break } }
            $value = $found
        }
        $value
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $ref = { param($Row, [string] $Key) & $lower (& $at $Row 'properties', $Key, 'id') }
    $leaf = { param([string] $Id) ($Id -split '/')[-1] }
    $byId = @{}
    foreach ($r in $Related) { if ($r) { $byId[(& $lower $r['id'])] = $r } }
    $siteByHost = @{}
    foreach ($s in $Site) { if ($s) { $siteByHost[(& $lower $s['host'])] = $s } }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }

    $clusters = [ordered]@{}
    $nodes = [ordered]@{}
    $edges = [System.Collections.Generic.List[object]]::new()
    $flows = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $gatewayRows = [System.Collections.Generic.List[object]]::new()
    $edgeSeen = @{}
    $addCluster = {
        param([string] $Id, [string] $Kind, [string] $Parent, [string] $Name, [string[]] $Detail, [string] $Icon)
        if (-not $clusters.Contains($Id)) { $clusters[$Id] = @{ id = $Id; kind = $Kind; parent = $Parent; name = $Name; detail = @($Detail | Where-Object { $_ }); icon = $Icon; external = $false; badges = @(); chips = @() } }
        $clusters[$Id]
    }
    $addEdge = {
        param([string] $From, [string] $To, [string] $Kind, [string] $Label)
        if (-not $From -or -not $To -or -not $nodes.Contains($From) -or -not $nodes.Contains($To)) { return }
        $key = "$From|$To|$Kind"
        if ($edgeSeen.Contains($key)) { return }
        $edgeSeen[$key] = $true
        $edges.Add(@{ id = "g$($edges.Count + 1)"; source = $From; target = $To; kind = $Kind; label = $Label; view = '' })
    }

    foreach ($gw in @($Gateway | Where-Object { $_ } | Sort-Object -Property { [string]$_['name'] })) {
        $gid = & $lower $gw['id']
        $gname = [string]$gw['name']
        $p = $gw['properties']
        $sub = & $lower $gw['subscriptionId']
        $group = [string]$gw['resourceGroup']
        $gwFindings = [System.Collections.Generic.List[object]]::new()
        $find = {
            param([string] $Severity, [string] $Component, [string] $Name, [string] $Title, [string] $Detail, [string] $Fix, [string] $NodeId)
            $f = [pscustomobject][ordered]@{ PSTypeName = 'AAC.ApplicationGatewayFinding'; Severity = $Severity; Gateway = $gname; Component = $Component; Name = $Name; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceGroup = $group; Subscription = & $subName $sub; ResourceId = $gid }
            $findings.Add($f); $gwFindings.Add($f)
            $target = if ($NodeId -and $nodes.Contains($NodeId)) { $nodes[$NodeId] } else { $null }
            if ($target) {
                $target.findings = @(@($target.findings) + "$($Severity): $Title - $Detail")
                if ($Severity -eq 'High' -or -not $target.risk) { $target.risk = $(if ($Severity -eq 'High') { 'high' } elseif ($Severity -eq 'Medium') { 'medium' } else { $target.risk }) }
            }
        }
        $node = {
            param([string] $Id, [string] $Name, [string] $Type, [string] $Label, [string] $Icon, [int] $Stage, [string[]] $Facts, [object[]] $Props, [string] $Portal)
            $Id = & $lower $Id
            if (-not $nodes.Contains($Id)) {
                $nodes[$Id] = @{
                    id = $Id; parent = $gid; name = $Name; type = $Type; typeLabel = $Label; icon = $Icon; kind = ''; location = [string]$gw['location']
                    resourceGroup = $group; subscriptionId = $sub; subscription = & $subName $sub; sku = ''; facts = @($Facts | Where-Object { $_ }); tags = $null
                    orphan = ''; external = $false; chips = @(); chip = ''; appliedTo = @(); risk = ''; rules = @(); routes = @(); propagation = ''
                    props = @($Props); findings = @(); health = ''; portal = $(if ($Portal) { $Portal } else { $gid }); elk = @{ 'elk.partitioning.partition' = [string]$Stage }
                }
            }
            $nodes[$Id]
        }

        # --- Boxes: subscription > resource group > network > subnet > gateway ------------------------------
        $subnetId = & $lower (& $at @(& $at $p 'gatewayIPConfigurations')[0] 'properties', 'subnet', 'id')
        $vnetId = if ($subnetId -match '^(.+/virtualnetworks/[^/]+)/subnets/') { $Matches[1] } else { '' }
        $vnet = if ($vnetId -and $byId.Contains($vnetId)) { $byId[$vnetId] } else { $null }
        $subscriptionBox = & $addCluster "/subscriptions/$sub" 'subscription' '' (& $subName $sub) @($sub) 'subscription'
        $parent = if ($vnet) {
            $vnetGroup = [string]$vnet['resourceGroup']
            $rg = & $addCluster "/subscriptions/$(& $lower $vnet['subscriptionId'])/resourcegroups/$(& $lower $vnetGroup)" 'resourcegroup' $(if ((& $lower $vnet['subscriptionId']) -eq $sub) { $subscriptionBox.id } else { (& $addCluster "/subscriptions/$(& $lower $vnet['subscriptionId'])" 'subscription' '' (& $subName (& $lower $vnet['subscriptionId'])) @() 'subscription').id }) $vnetGroup @() 'resourcegroup'
            $v = & $addCluster $vnetId 'vnet' $rg.id ([string]$vnet['name']) @((@(& $at $vnet 'properties', 'addressSpace', 'addressPrefixes') -join ', ')) 'vnet'
            $subnetRow = @(@(& $at $vnet 'properties', 'subnets') | Where-Object { (& $lower (& $at $_ 'id')) -eq $subnetId })[0]
            $nsg = & $leaf (& $lower (& $at $subnetRow 'properties', 'networkSecurityGroup', 'id'))
            $udr = & $leaf (& $lower (& $at $subnetRow 'properties', 'routeTable', 'id'))
            (& $addCluster $subnetId 'subnet' $v.id (& $leaf $subnetId) @([string](& $at $subnetRow 'properties', 'addressPrefix'), $(if ($nsg) { "NSG: $nsg" }), $(if ($udr) { "UDR: $udr" })) 'subnet').id
        }
        else { (& $addCluster "/subscriptions/$sub/resourcegroups/$(& $lower $group)" 'resourcegroup' $subscriptionBox.id $group @() 'resourcegroup').id }

        $sku = & $at $p 'sku'
        $tier = [string](& $at $sku 'tier')
        $autoscale = & $at $p 'autoscaleConfiguration'
        $zones = @(& $at $gw 'zones' | Where-Object { $_ })
        $sslPolicy = & $at $p 'sslPolicy'
        $tls = if (& $at $sslPolicy 'policyName') { [string](& $at $sslPolicy 'policyName') } elseif (& $at $sslPolicy 'minProtocolVersion') { "Custom, min $(& $at $sslPolicy 'minProtocolVersion')" } else { 'Default (AppGwSslPolicy20150501)' }
        $capacity = if ($autoscale) { "autoscale $(& $at $autoscale 'minCapacity')-$(& $at $autoscale 'maxCapacity')" } else { "$(& $at $sku 'capacity') instance(s)" }
        $box = & $addCluster $gid 'appgw' $parent $gname @([string](& $at $sku 'name'), $(if ($zones.Count) { "zones $($zones -join ',')" } else { 'no zones' }), $capacity, "TLS $tls", [string](& $at $p 'operationalState')) 'appgw'
        $box.elk = @{ 'elk.partitioning.activate' = 'true' }
        $box.props = @(@('SKU', [string](& $at $sku 'name')), @('Tier', $tier), @('Capacity', $capacity), @('Zones', $(if ($zones.Count) { $zones -join ', ' } else { 'none' })), @('TLS policy', $tls), @('HTTP/2', [string](& $at $p 'enableHttp2')), @('State', [string](& $at $p 'operationalState')), @('Subnet', $subnetId))
        $box.findings = @()
        $box.risk = ''

        # --- Cards --------------------------------------------------------------------------------------------
        $ports = @{}
        foreach ($fp in @(& $at $p 'frontendPorts' | Where-Object { $null -ne $_ })) { $ports[(& $lower $fp['id'])] = [string](& $at $fp 'properties', 'port') }
        foreach ($fe in @(& $at $p 'frontendIPConfigurations' | Where-Object { $null -ne $_ })) {
            $pipId = & $ref $fe 'publicIPAddress'
            $ip = if ($pipId -and $byId.Contains($pipId)) { [string](& $at $byId[$pipId] 'properties', 'ipAddress') } else { [string](& $at $fe 'properties', 'privateIPAddress') }
            $null = & $node $fe['id'] ([string]$fe['name']) 'appgw/frontend' $(if ($pipId) { 'Frontend IP (public)' } else { 'Frontend IP (private)' }) $(if ($pipId) { 'pip' } else { 'nic' }) 0 @($ip) @(@('IP address', $ip), @('Public IP', (& $leaf $pipId))) ''
        }
        $wafPolicies = @{}
        $globalPolicy = & $ref @{ properties = $p } 'firewallPolicy'
        $policyNode = {
            param([string] $PolicyId)
            if (-not $PolicyId) { return $null }
            $row = $byId[$PolicyId]
            $mode = [string](& $at $row 'properties', 'policySettings', 'mode')
            $state = [string](& $at $row 'properties', 'policySettings', 'state')
            $sets = @(@(& $at $row 'properties', 'managedRules', 'managedRuleSets') | ForEach-Object { "$(& $at $_ 'ruleSetType') $(& $at $_ 'ruleSetVersion')" })
            $n = & $node $PolicyId (& $leaf $PolicyId) 'microsoft.network/applicationgatewaywebapplicationfirewallpolicies' 'WAF policy' 'waf' 0 @("$mode$(if ($state -eq 'Disabled') { ', disabled' })", ($sets -join ', ')) @(@('Mode', $mode), @('State', $state), @('Rule sets', ($sets -join ', ')), @('Custom rules', [string]@(& $at $row 'properties', 'customRules').Count)) $PolicyId
            $wafPolicies[$PolicyId] = @{ Mode = $mode; State = $state; Sets = $sets; Read = [bool]$row }
            $n
        }
        $null = & $policyNode $globalPolicy

        $certs = @{}
        foreach ($c in @(& $at $p 'sslCertificates' | Where-Object { $null -ne $_ })) {
            $expires = $null
            $data = [string](& $at $c 'properties', 'publicCertData')
            if ($data) {
                try {
                    $collection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
                    $collection.Import([Convert]::FromBase64String($data))
                    $all = @($collection)
                    $leafCert = @($all | Where-Object { $subject = $_.Subject; -not @($all | Where-Object { $_.Issuer -eq $subject -and $_.Subject -ne $subject }).Count } | Sort-Object NotAfter)[0]
                    if ($leafCert) { $expires = $leafCert.NotAfter.ToUniversalTime() }
                }
                catch { $expires = $null }
            }
            $certs[(& $lower $c['id'])] = @{ Name = [string]$c['name']; KeyVault = [string](& $at $c 'properties', 'keyVaultSecretId'); Expires = $expires }
        }

        $listenerIds = @{}
        foreach ($l in @(& $at $p 'httpListeners' | Where-Object { $null -ne $_ })) {
            $lid = & $lower $l['id']
            $protocol = [string](& $at $l 'properties', 'protocol')
            $port = $ports[(& $ref $l 'frontendPort')]
            $hosts = @(@(& $at $l 'properties', 'hostNames') + @(& $at $l 'properties', 'hostName') | Where-Object { $_ } | Select-Object -Unique)
            $cert = $certs[(& $ref $l 'sslCertificate')]
            $policy = & $ref $l 'firewallPolicy'
            $n = & $node $lid ([string]$l['name']) 'appgw/listener' 'Listener' 'appgw' 1 @("$protocol $port", ($hosts -join ', '), $(if ($cert -and $cert.Expires) { "cert to $($cert.Expires.ToString('yyyy-MM-dd'))" })) @(
                @('Protocol', $protocol), @('Port', $port), @('Host names', $(if ($hosts.Count) { $hosts -join ', ' } else { '(any - basic listener)' })), @('Certificate', $(if ($cert) { "$($cert.Name)$(if ($cert.KeyVault) { ' (Key Vault)' } else { ' (uploaded)' })" })),
                @('Certificate expires', $(if ($cert -and $cert.Expires) { $cert.Expires.ToString('yyyy-MM-dd') })), @('WAF policy', $(if ($policy) { & $leaf $policy } elseif ($globalPolicy) { "$(& $leaf $globalPolicy) (gateway)" })))
            $listenerIds[$lid] = @{ Protocol = $protocol; Port = $port; Hosts = $hosts; Cert = $cert; Policy = $(if ($policy) { $policy } else { $globalPolicy }); Used = $false }
            $null = & $addEdge (& $lower (& $ref $l 'frontendIPConfiguration')) $lid 'flow' $port
            $null = & $policyNode $policy
            if ($policy) { $null = & $addEdge $policy $lid 'waf' 'per site' } elseif ($globalPolicy) { $null = & $addEdge $globalPolicy $lid 'waf' '' }
        }
        $settingsIds = @{}
        foreach ($s in @(& $at $p 'backendHttpSettingsCollection' | Where-Object { $null -ne $_ })) {
            $sid = & $lower $s['id']
            $sp = & $at $s 'properties'
            $hostMode = if ((& $at $sp 'pickHostNameFromBackendAddress') -eq $true) { 'pick from backend' } elseif (& $at $sp 'hostName') { "override: $(& $at $sp 'hostName')" } else { 'from request' }
            $draining = & $at $sp 'connectionDraining'
            $null = & $node $sid ([string]$s['name']) 'appgw/settings' 'Backend settings' 'appgw' 4 @("$(& $at $sp 'protocol') $(& $at $sp 'port')", "$(& $at $sp 'requestTimeout') s") @(
                @('Protocol', [string](& $at $sp 'protocol')), @('Port', [string](& $at $sp 'port')), @('Request timeout', "$(& $at $sp 'requestTimeout') s"), @('Host name', $hostMode),
                @('Cookie affinity', [string](& $at $sp 'cookieBasedAffinity')), @('Connection draining', $(if ((& $at $draining 'enabled') -eq $true) { "on, $(& $at $draining 'drainTimeoutInSec') s" } else { 'off' })), @('Custom probe', $(& $leaf (& $ref $s 'probe'))), @('Path override', [string](& $at $sp 'path')))
            $settingsIds[$sid] = @{ Row = $s; Used = $false; Probe = (& $ref $s 'probe') }
        }
        $probeIds = @{}
        foreach ($pr in @(& $at $p 'probes' | Where-Object { $null -ne $_ })) {
            $prid = & $lower $pr['id']
            $pp = & $at $pr 'properties'
            $null = & $node $prid ([string]$pr['name']) 'appgw/probe' 'Health probe' 'monitor' 5 @("$(& $at $pp 'protocol') $(& $at $pp 'path')", "every $(& $at $pp 'interval') s") @(
                @('Protocol', [string](& $at $pp 'protocol')), @('Host', $(if ((& $at $pp 'pickHostNameFromBackendHttpSettings') -eq $true) { 'from backend settings' } else { [string](& $at $pp 'host') })), @('Path', [string](& $at $pp 'path')),
                @('Interval', "$(& $at $pp 'interval') s"), @('Timeout', "$(& $at $pp 'timeout') s"), @('Unhealthy after', "$(& $at $pp 'unhealthyThreshold') failures"), @('Healthy status codes', (@(& $at $pp 'match', 'statusCodes') -join ', ')))
            $probeIds[$prid] = @{ Row = $pr; Used = $false }
        }
        foreach ($sid in @($settingsIds.Keys)) { if ($settingsIds[$sid].Probe) { $probeIds[$settingsIds[$sid].Probe].Used = $true; $null = & $addEdge $sid $settingsIds[$sid].Probe 'probe' '' } }

        # Pools, their targets, and health.
        $metrics = if ($Health.Metrics.Contains($gid)) { $Health.Metrics[$gid] } else { @{} }
        $live = if ($Health.Live.Contains($gid)) { @($Health.Live[$gid]) } else { @() }
        $state = { param([int] $Healthy, [int] $Unhealthy, [bool] $Known) if (-not $Known) { 'unknown' } elseif ($Unhealthy -and -not $Healthy) { 'unhealthy' } elseif ($Unhealthy) { 'degraded' } elseif ($Healthy) { 'healthy' } else { 'unknown' } }
        $poolIds = @{}
        foreach ($pool in @(& $at $p 'backendAddressPools' | Where-Object { $null -ne $_ })) {
            $poid = & $lower $pool['id']
            $poolName = [string]$pool['name']
            $addresses = @(@(& $at $pool 'properties', 'backendAddresses') | ForEach-Object { $a = [string](& $at $_ 'fqdn'); if (-not $a) { $a = [string](& $at $_ 'ipAddress') }; $a } | Where-Object { $_ })
            $configurations = @(@(& $at $pool 'properties', 'backendIPConfigurations') | ForEach-Object { & $lower (& $at $_ 'id') } | Where-Object { $_ })
            $poolLive = @($live | Where-Object { $_.Pool -eq $poid })
            $metricKeys = @($metrics.Keys | Where-Object { $_ -like "$($poolName.ToLowerInvariant())|*" })
            $healthy = 0; $unhealthy = 0; $known = $false
            if ($poolLive.Count) {
                $known = $true
                foreach ($server in @($poolLive | Group-Object -Property Address)) { if (@($server.Group | Where-Object { $_.Health -ne 'Healthy' }).Count) { $unhealthy++ } else { $healthy++ } }
            }
            elseif ($metricKeys.Count) {
                $known = $true
                $healthy = [int](@($metricKeys | ForEach-Object { [double]$metrics[$_].Healthy }) | Measure-Object -Maximum).Maximum
                $unhealthy = [int](@($metricKeys | ForEach-Object { [double]$metrics[$_].Unhealthy }) | Measure-Object -Maximum).Maximum
            }
            $poolHealth = & $state $healthy $unhealthy $known
            $n = & $node $poid $poolName 'appgw/pool' 'Backend pool' 'appgw' 5 @("$($addresses.Count + $configurations.Count) target(s)", $(if ($known) { "$healthy healthy, $unhealthy unhealthy" })) @(@('Targets', [string]($addresses.Count + $configurations.Count)), @('Healthy', $(if ($known) { [string]$healthy })), @('Unhealthy', $(if ($known) { [string]$unhealthy })), @('Health from', $(if ($poolLive.Count) { 'live backend health check' } elseif ($metricKeys.Count) { 'metrics, last 30 minutes' } else { 'not known' })))
            $n.health = $poolHealth
            $poolIds[$poid] = @{ Name = $poolName; Count = $addresses.Count + $configurations.Count; Healthy = $healthy; Unhealthy = $unhealthy; Known = $known; Used = $false; Targets = @() }
            $targets = @(
                foreach ($a in $addresses) {
                    $siteRow = $siteByHost[$a.ToLowerInvariant()]
                    @{ Id = "$poid/targets/$($a.ToLowerInvariant())"; Name = $(if ($siteRow) { [string]$siteRow['name'] } else { $a }); Address = $a; Label = $(if ($siteRow) { 'App Service' } elseif ($a -match '^\d+\.\d+\.\d+\.\d+$') { 'IP address' } else { 'FQDN' }); Icon = $(if ($siteRow) { if ([string]$siteRow['kind'] -match 'functionapp') { 'functionapp' } else { 'appservice' } } else { 'resource' }); Portal = $(if ($siteRow) { [string]$siteRow['id'] } else { '' }) }
                }
                foreach ($cfg in $configurations) {
                    $nicId = ($cfg -split '/ipconfigurations/')[0]
                    $nic = $byId[$nicId]
                    $vmId = & $lower (& $at $nic 'properties', 'virtualMachine', 'id')
                    $ip = [string](@(@(& $at $nic 'properties', 'ipConfigurations') | Where-Object { (& $lower (& $at $_ 'id')) -eq $cfg } | ForEach-Object { & $at $_ 'properties', 'privateIPAddress' })[0])
                    @{ Id = "$poid/targets/$cfg"; Name = $(if ($vmId) { & $leaf $vmId } else { & $leaf $nicId }); Address = $ip; Label = $(if ($vmId) { 'Virtual machine' } else { 'Network interface' }); Icon = $(if ($vmId) { 'vm' } else { 'nic' }); Portal = $(if ($vmId) { $vmId } else { $nicId }) }
                })
            foreach ($t in $targets) {
                $mine = @($poolLive | Where-Object { $_.Address -eq $t.Address })
                $tn = & $node $t.Id $t.Name 'appgw/target' $t.Label $t.Icon 6 @($t.Address, $(if ($mine.Count) { (@($mine.Health | Select-Object -Unique) -join '/') })) @(@('Address', $t.Address), @('Health', $(if ($mine.Count) { (@($mine | ForEach-Object { "$($_.Health) via $(& $leaf $_.Settings)" }) -join '; ') })), @('Probe says', $(if ($mine.Count) { (@($mine | Where-Object { $_.Health -ne 'Healthy' -and $_.Reason } | ForEach-Object { $_.Reason } | Select-Object -Unique) -join ' | ') }))) $t.Portal
                if ($mine.Count) { $tn.health = & $state @($mine | Where-Object Health -EQ 'Healthy').Count @($mine | Where-Object Health -NE 'Healthy').Count $true }
                $null = & $addEdge $poid $t.Id 'flow' ''
            }
            $poolIds[$poid].Targets = @($targets | ForEach-Object { $_.Name })
        }

        $redirects = @{}
        foreach ($rd in @(& $at $p 'redirectConfigurations' | Where-Object { $null -ne $_ })) {
            $rdid = & $lower $rd['id']
            $rp = & $at $rd 'properties'
            $to = if (& $ref $rd 'targetListener') { & $leaf (& $ref $rd 'targetListener') } else { [string](& $at $rp 'targetUrl') }
            $null = & $node $rdid ([string]$rd['name']) 'appgw/redirect' 'Redirect' 'appgw' 3 @("$(& $at $rp 'redirectType') to $to") @(@('Type', [string](& $at $rp 'redirectType')), @('To', $to), @('Include path', [string](& $at $rp 'includePath')), @('Include query string', [string](& $at $rp 'includeQueryString')))
            $redirects[$rdid] = @{ Target = (& $ref $rd 'targetListener'); Url = [string](& $at $rp 'targetUrl'); To = $to }
            $null = & $addEdge $rdid (& $ref $rd 'targetListener') 'redirect' ''
        }
        $rewrites = @{}
        foreach ($rw in @(& $at $p 'rewriteRuleSets' | Where-Object { $null -ne $_ })) { $rewrites[(& $lower $rw['id'])] = [string]$rw['name'] }
        $paths = @{}
        foreach ($pm in @(& $at $p 'urlPathMaps' | Where-Object { $null -ne $_ })) { $paths[(& $lower $pm['id'])] = $pm }

        # --- Rules and the flows they make ---------------------------------------------------------------------
        foreach ($rule in @(& $at $p 'requestRoutingRules' | Where-Object { $null -ne $_ } | Sort-Object -Property { [int](& $at $_ 'properties', 'priority') })) {
            $rid = & $lower $rule['id']
            $rp = & $at $rule 'properties'
            $type = [string](& $at $rp 'ruleType')
            $priority = [string](& $at $rp 'priority')
            $lid = & $ref $rule 'httpListener'
            $null = & $node $rid ([string]$rule['name']) 'appgw/rule' $(if ($priority) { "Rule (priority $priority)" } else { 'Rule' }) 'appgw' 2 @($(if ($type -eq 'PathBasedRouting') { 'path-based' } else { 'basic' })) @(@('Type', $type), @('Priority', $priority), @('Listener', (& $leaf $lid)), @('Rewrite set', $rewrites[(& $ref $rule 'rewriteRuleSet')]))
            if ($listenerIds.Contains($lid)) { $listenerIds[$lid].Used = $true }
            $null = & $addEdge $lid $rid 'flow' ''
            $entries = if ($type -eq 'PathBasedRouting') {
                $pm = $paths[(& $ref $rule 'urlPathMap')]
                foreach ($pr in @(& $at $pm 'properties', 'pathRules' | Where-Object { $null -ne $_ })) { @{ Id = & $lower $pr['id']; Name = [string]$pr['name']; Paths = (@(& $at $pr 'properties', 'paths') -join ', '); Pool = (& $ref $pr 'backendAddressPool'); Settings = (& $ref $pr 'backendHttpSettings'); Redirect = (& $ref $pr 'redirectConfiguration'); Rewrite = (& $ref $pr 'rewriteRuleSet'); Policy = (& $ref $pr 'firewallPolicy') } }
                if ($pm) { @{ Id = "$(& $lower $pm['id'])/default"; Name = "$($pm['name']) (default)"; Paths = '(default)'; Pool = (& $ref $pm 'defaultBackendAddressPool'); Settings = (& $ref $pm 'defaultBackendHttpSettings'); Redirect = (& $ref $pm 'defaultRedirectConfiguration'); Rewrite = (& $ref $pm 'defaultRewriteRuleSet'); Policy = '' } }
            }
            else { @{ Id = ''; Name = ''; Paths = '*'; Pool = (& $ref $rule 'backendAddressPool'); Settings = (& $ref $rule 'backendHttpSettings'); Redirect = (& $ref $rule 'redirectConfiguration'); Rewrite = (& $ref $rule 'rewriteRuleSet'); Policy = '' } }
            foreach ($e in @($entries)) {
                $from = $rid
                if ($e.Id) {
                    $null = & $node $e.Id $e.Name 'appgw/path' 'Path rule' 'appgw' 3 @($e.Paths) @(@('Paths', $e.Paths), @('Rewrite set', $rewrites[$e.Rewrite]), @('WAF policy', (& $leaf $e.Policy)))
                    $null = & $addEdge $rid $e.Id 'flow' ''
                    if ($e.Policy) { $null = & $policyNode $e.Policy; $null = & $addEdge $e.Policy $e.Id 'waf' 'per path' }
                    $from = $e.Id
                }
                if ($e.Redirect) { $null = & $addEdge $from $e.Redirect 'flow' 'redirect' }
                if ($e.Settings) { $null = & $addEdge $from $e.Settings 'flow' ''; if ($settingsIds.Contains($e.Settings)) { $settingsIds[$e.Settings].Used = $true } }
                if ($e.Settings -and $e.Pool) { $null = & $addEdge $e.Settings $e.Pool 'flow' '' }
                $poolInfo = if ($e.Pool -and $poolIds.Contains($e.Pool)) { $poolIds[$e.Pool]; $poolIds[$e.Pool].Used = $true } else { $null }
                $listener = $listenerIds[$lid]
                $sRow = if ($e.Settings -and $settingsIds.Contains($e.Settings)) { $settingsIds[$e.Settings].Row } else { $null }
                $redirect = if ($e.Redirect) { $redirects[$e.Redirect] } else { $null }
                $policyId = if ($e.Policy) { $e.Policy } elseif ($listener) { $listener.Policy } else { '' }
                $flows.Add([pscustomobject][ordered]@{
                        PSTypeName      = 'AAC.ApplicationGatewayFlow'
                        Gateway         = $gname
                        Listener        = & $leaf $lid
                        Protocol        = $(if ($listener) { $listener.Protocol })
                        Port            = $(if ($listener) { $listener.Port })
                        HostNames       = $(if ($listener) { $listener.Hosts -join ', ' })
                        Certificate     = $(if ($listener -and $listener.Cert) { $listener.Cert.Name })
                        CertExpires     = $(if ($listener -and $listener.Cert) { $listener.Cert.Expires })
                        WafPolicy       = & $leaf $policyId
                        WafMode         = $(if ($policyId -and $wafPolicies.Contains($policyId)) { $wafPolicies[$policyId].Mode })
                        Rule            = [string]$rule['name']
                        Priority        = $priority
                        Path            = $e.Paths
                        Redirect        = $(if ($redirect) { $redirect.To })
                        Rewrite         = $rewrites[$e.Rewrite]
                        BackendSettings = & $leaf $e.Settings
                        BackendPort     = $(if ($sRow) { [string](& $at $sRow 'properties', 'port') })
                        Probe           = $(if ($sRow) { & $leaf (& $ref $sRow 'probe') })
                        Pool            = & $leaf $e.Pool
                        Targets         = $(if ($poolInfo) { $poolInfo.Targets -join ', ' })
                        Healthy         = $(if ($poolInfo -and $poolInfo.Known) { $poolInfo.Healthy })
                        Unhealthy       = $(if ($poolInfo -and $poolInfo.Known) { $poolInfo.Unhealthy })
                        Health          = $(if ($poolInfo) { & $state $poolInfo.Healthy $poolInfo.Unhealthy $poolInfo.Known } elseif ($redirect) { 'redirect' } else { '' })
                        ResourceId      = $gid
                    })
            }
        }

        # --- Findings ------------------------------------------------------------------------------------------
        $isV2 = $tier -in 'Standard_v2', 'WAF_v2', 'Basic'
        if (-not $isV2) { & $find 'High' 'Gateway' $gname 'v1 SKU (retired)' "Tier ${tier}: Application Gateway v1 is retired." 'Migrate to Standard_v2 or WAF_v2 (Microsoft''s migration script copies the configuration).' $gid }
        $wafConfig = & $at $p 'webApplicationFirewallConfiguration'
        if ($tier -like 'WAF*' -and -not $globalPolicy -and (& $at $wafConfig 'enabled') -ne $true) { & $find 'High' 'WAF' $gname 'WAF tier without a WAF' 'The gateway pays for WAF but has no WAF policy or enabled configuration.' 'Associate a WAF policy in Prevention mode.' $gid }
        if ($tier -notlike 'WAF*' -and @($listenerIds.Values | Where-Object { $_.Protocol -eq 'Https' }).Count) { & $find 'Medium' 'WAF' $gname 'Public HTTPS without a WAF' "Tier $tier inspects no traffic." 'Move to WAF_v2 with a WAF policy, or put Front Door with WAF in front.' $gid }
        foreach ($policyId in @($wafPolicies.Keys)) {
            $w = $wafPolicies[$policyId]
            if (-not $w.Read) { continue }
            if ($w.Mode -eq 'Detection') { & $find 'High' 'WAF' (& $leaf $policyId) 'WAF policy in Detection mode' 'Attacks are logged, not blocked.' 'Tune exclusions from the logs, then switch to Prevention.' $policyId }
            if ($w.State -eq 'Disabled') { & $find 'High' 'WAF' (& $leaf $policyId) 'WAF policy disabled' 'The policy is attached but doesn''t inspect anything.' 'Enable the policy.' $policyId }
            foreach ($set in $w.Sets) {
                if ($set -match '^OWASP (\d+\.\d+)' -and [version]$Matches[1] -lt [version]'3.2') { & $find 'Low' 'WAF' (& $leaf $policyId) 'Old managed rule set' "$set." 'Upgrade to the Default Rule Set (DRS 2.1) or OWASP 3.2.' $policyId }
            }
        }
        if ($tls -match '20150501|20170401$|TLSv1_0|TLSv1_1') { & $find 'Medium' 'TLS' $gname 'Old TLS policy' "TLS policy: $tls - TLS 1.0/1.1 or weak ciphers allowed." 'Use AppGwSslPolicy20220101 (or 20220101S) or a custom policy with TLS 1.2 minimum.' $gid }
        if ($isV2 -and ((-not $zones.Count) -or ($autoscale -and [int](& $at $autoscale 'minCapacity') -lt 2) -or (-not $autoscale -and [int](& $at $sku 'capacity') -lt 2))) { & $find 'Medium' 'Gateway' $gname 'Not zone-redundant or under 2 instances' "$capacity; $(if ($zones.Count) { "zones $($zones -join ',')" } else { 'no zones' })." 'Deploy across zones 1, 2 and 3 with a minimum of 2 instances.' $gid }
        foreach ($lid in @($listenerIds.Keys)) {
            $l = $listenerIds[$lid]
            $lname = & $leaf $lid
            if (-not $l.Used) { & $find 'Low' 'Listener' $lname 'Listener no rule uses' "$($l.Protocol) $($l.Port)." 'Delete it, or add the rule it was meant for.' $lid; $nodes[$lid].orphan = 'no rule uses it' }
            if ($l.Protocol -eq 'Http' -and $l.Used) {
                $toHttps = @($flows | Where-Object { $_.ResourceId -eq $gid -and $_.Listener -eq $lname -and $_.Redirect -and @($listenerIds.Values | Where-Object { $_.Protocol -eq 'Https' }).Count })
                if (-not $toHttps.Count) { & $find 'Medium' 'Listener' $lname 'HTTP not redirected to HTTPS' "Port $($l.Port) serves plain HTTP." 'Redirect it (permanent) to the HTTPS listener.' $lid }
            }
            if ($l.Cert) {
                if ($l.Cert.Expires -and $l.Cert.Expires -lt $Now) { & $find 'High' 'Certificate' $l.Cert.Name 'Certificate expired' "Expired $($l.Cert.Expires.ToString('yyyy-MM-dd')) - listener $lname." 'Renew it; with Key Vault, the gateway picks up the new version within 4 hours.' $lid }
                elseif ($l.Cert.Expires -and ($l.Cert.Expires - $Now).TotalDays -le $CertificateDays) { & $find 'Medium' 'Certificate' $l.Cert.Name "Certificate expires within $CertificateDays days" "Expires $($l.Cert.Expires.ToString('yyyy-MM-dd')) - listener $lname." 'Renew it now.' $lid }
                if (-not $l.Cert.KeyVault) { & $find 'Medium' 'Certificate' $l.Cert.Name 'Certificate uploaded, not from Key Vault' "Listener $lname." 'Store it in Key Vault and reference it, so renewals reach the gateway automatically.' $lid }
            }
        }
        foreach ($sid in @($settingsIds.Keys)) {
            $si = $settingsIds[$sid]
            $sname = & $leaf $sid
            $sp = & $at $si.Row 'properties'
            if (-not $si.Used) { & $find 'Low' 'Backend settings' $sname 'Backend settings no rule uses' '' 'Delete them.' $sid; $nodes[$sid].orphan = 'no rule uses them'; continue }
            if (-not $si.Probe) { & $find 'Medium' 'Backend settings' $sname 'No custom health probe' 'The default probe calls / on the target''s IP with the setting''s host - often not what the app answers.' 'Add a custom probe on a health endpoint, with the right host.' $sid }
            else {
                $pp = & $at $probeIds[$si.Probe].Row 'properties'
                $settingsHost = if ((& $at $sp 'pickHostNameFromBackendAddress') -eq $true) { 'backend' } else { [string](& $at $sp 'hostName') }
                $probeHost = if ((& $at $pp 'pickHostNameFromBackendHttpSettings') -eq $true) { $settingsHost } else { [string](& $at $pp 'host') }
                # Only two explicit host names that differ: picking the host from the backend is a valid pairing.
                if ($settingsHost -and $settingsHost -ne 'backend' -and $probeHost -and $probeHost -ne 'backend' -and $probeHost -ne $settingsHost) { & $find 'Medium' 'Probe' (& $leaf $si.Probe) 'Probe host differs from the backend settings' "Probe asks for '$probeHost', traffic goes with '$settingsHost'." 'Let the probe pick the host from the backend settings, or match them.' $si.Probe }
            }
            if ((& $at $sp 'connectionDraining', 'enabled') -ne $true) { & $find 'Low' 'Backend settings' $sname 'Connection draining off' 'Removing or updating a target drops its in-flight requests.' 'Turn on connection draining (30-60 s).' $sid }
        }
        foreach ($prid in @($probeIds.Keys)) { if (-not $probeIds[$prid].Used) { & $find 'Low' 'Probe' (& $leaf $prid) 'Probe no backend setting uses' '' 'Delete it, or attach it to the backend settings it was meant for.' $prid; $nodes[$prid].orphan = 'no backend setting uses it' } }
        foreach ($poid in @($poolIds.Keys)) {
            $po = $poolIds[$poid]
            if (-not $po.Used) { & $find 'Low' 'Pool' $po.Name 'Backend pool no rule uses' "$($po.Count) target(s)." 'Delete it, or route to it.' $poid; $nodes[$poid].orphan = 'no rule uses it'; continue }
            if (-not $po.Count) { & $find 'High' 'Pool' $po.Name 'Rule sends traffic to an empty pool' 'Requests to it get 502.' 'Add targets, or point the rule elsewhere.' $poid; continue }
            if ($po.Known -and $po.Unhealthy -and -not $po.Healthy) { & $find 'High' 'Pool' $po.Name 'Every target unhealthy' "$($po.Unhealthy) unhealthy - requests get 502." 'Check the probe (-IncludeHealth shows its reason), the NSG on the targets, and the targets themselves.' $poid }
            elseif ($po.Known -and $po.Unhealthy) { & $find 'Medium' 'Pool' $po.Name 'Some targets unhealthy' "$($po.Healthy) healthy, $($po.Unhealthy) unhealthy." 'Find the failing targets (-IncludeHealth gives the probe''s reason).' $poid }
        }
        if ($Health.Errors.Contains($gid)) { & $find 'Info' 'Health' $gname 'Live backend health not read' ([string]$Health.Errors[$gid]) 'Run with an account allowed Microsoft.Network/applicationGateways/backendhealth/action, or rely on the metrics.' $gid }

        $box.findings = @($gwFindings | Where-Object { $_.Component -in 'Gateway', 'WAF', 'TLS', 'Health' -and $_.ResourceId -eq $gid } | ForEach-Object { "$($_.Severity): $($_.Finding) - $($_.Detail)" })
        if (@($gwFindings | Where-Object Severity -EQ 'High').Count) { $box.risk = 'high' }
        $gatewayRows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.ApplicationGateway'; Gateway = $gname; Sku = [string](& $at $sku 'name'); Tier = $tier; Capacity = $capacity; Zones = ($zones -join ','); TlsPolicy = $tls
                State = [string](& $at $p 'operationalState'); Listeners = $listenerIds.Count; Rules = @(& $at $p 'requestRoutingRules' | Where-Object { $null -ne $_ }).Count; Pools = $poolIds.Count
                Targets = [int](@($poolIds.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum
                Unhealthy = [int](@($poolIds.Values | Where-Object Known | ForEach-Object { $_.Unhealthy }) | Measure-Object -Sum).Sum
                WafPolicy = (& $leaf $globalPolicy); Findings = $gwFindings.Count; High = @($gwFindings | Where-Object Severity -EQ 'High').Count
                Subnet = $subnetId; ResourceGroup = $group; Subscription = & $subName $sub; ResourceId = $gid
            })
    }

    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $depth = { param($C) $d = 0; $x = $C.parent; while ($x -and $clusters.Contains($x)) { $d++; $x = $clusters[$x].parent }; $d }
    @{
        Clusters = @($clusters.Values | Sort-Object -Property { & $depth $_ } -Stable)
        Nodes    = @($nodes.Values)
        Edges    = $edges.ToArray()
        Gateways = $gatewayRows.ToArray()
        Flows    = $flows.ToArray()
        Findings = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Gateway, Component)
        Stats    = @{
            Gateways  = $gatewayRows.Count
            Listeners = @($nodes.Values | Where-Object { $_.type -eq 'appgw/listener' }).Count
            Rules     = @($nodes.Values | Where-Object { $_.type -eq 'appgw/rule' }).Count
            Pools     = @($nodes.Values | Where-Object { $_.type -eq 'appgw/pool' }).Count
            Targets   = @($nodes.Values | Where-Object { $_.type -eq 'appgw/target' }).Count
            Unhealthy = $(if ($gatewayRows.Count) { [int](($gatewayRows | Measure-Object -Property Unhealthy -Sum).Sum) } else { 0 })
            Findings  = $findings.Count
            High      = @($findings | Where-Object Severity -EQ 'High').Count
            Connections = $edges.Count
        }
    }
}
