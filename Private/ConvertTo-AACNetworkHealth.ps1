function ConvertTo-AACNetworkHealth {
    <#
    .SYNOPSIS
        Turns network resources, their metrics and Resource Health into
        health per component (AAC.NetworkHealth), findings and a heat map.
    .DESCRIPTION
        No Azure calls. Components: ExpressRoute circuits, ExpressRoute
        gateways, VPN gateways, point-to-site gateways, connections, Azure
        Firewalls, NAT gateways. Per component:
          Availability     the lowest of what applies: BGP and ARP
                           availability per peering and link, firewall
                           health, NAT data path, BGP peer status, a
                           connection being Connected (100) or not (0)
          PeakUtilization  % of capacity at the peak: an ExpressRoute link's
                           bits per second against the circuit's bandwidth, a
                           VPN gateway's bandwidth against its SKU, a
                           firewall's throughput against its tier
          Drops            QoS drops (bits/s), tunnel packet drops, NAT
                           dropped packets
          Capacity         the highest % of a limit: gateway CPU, packets per
                           second against the SKU, routes advertised (1,000)
                           and learned (4,000), SNAT ports, point-to-site
                           connections against the SKU
          Health           Resource Health, and provisioning state
        Limits are Microsoft's published figures per SKU, approximate.

        Findings (AAC.NetworkHealthFinding: Severity, Component, Name, Signal,
        Finding, Detail, When - 'peak at ...', '... to ...' or 'since ...',
        in UTC - FirstSeen, LastSeen, Recommendation). Components carry
        PeakAt (when utilisation, CPU or SNAT peaked) and HealthSince. The heat map scores every component
        0-100 per signal - the 40 worst. Returns @{ Components; Findings;
        HeatMap; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Invoke-AACGraphBatch's rows by query name (Get-AACNetworkHealthQuery).
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Read,

        # Read-AACNetworkHealthMetric's result.
        [hashtable] $Metric = @{},

        [ValidateRange(50, 99)]
        [int] $WarnPercent = 80,

        [hashtable] $SubscriptionName = @{}
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
    $rows = { param([string] $Name) @(if ($Read.Contains($Name)) { $Read[$Name] | Where-Object { $null -ne $_ } }) }
    $subName = { param([string] $Id) if ($SubscriptionName.Contains($Id)) { $SubscriptionName[$Id] } else { $Id } }
    $round = { param($Value, [int] $Digits = 1) if ($null -eq $Value) { $null } else { [Math]::Round([double]$Value, $Digits) } }
    # Series of one call; their points' values.
    $seriesOf = { param([string] $Id, [string] $Key) if ($Metric.Contains($Id) -and $Metric[$Id].Contains($Key) -and -not $Metric[$Id][$Key].Error) { @($Metric[$Id][$Key].Series) } else { @() } }
    $readOk = { param([string] $Id, [string] $Key) $Metric.Contains($Id) -and $Metric[$Id].Contains($Key) -and -not $Metric[$Id][$Key].Error }
    $values = { param([object[]] $Series, [string] $Name, [string] $Field) @(foreach ($s in $Series) { if ($s.Name -eq $Name) { foreach ($p in $s.Points) { if ($null -ne $p[$Field]) { [double]$p[$Field] } } } }) }
    $max = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Maximum).Maximum } else { $null } }
    $min = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Minimum).Minimum } else { $null } }
    $mean = { param($Numbers) $n = @($Numbers | Where-Object { $null -ne $_ }); if ($n.Count) { ($n | Measure-Object -Average).Average } else { $null } }
    $sum = { param($Numbers) $t = 0.0; foreach ($n in @($Numbers)) { if ($null -ne $n) { $t += [double]$n } }; $t }
    # When: a point's time (UTC); the time of a series' peak (or low); the first and last point that matches.
    $timeOf = {
        param($Point)
        $t = if ($Point -is [System.Collections.IDictionary] -and $Point.Contains('timeStamp')) { $Point['timeStamp'] } else { $null }
        if ($t -is [datetime]) { $t.ToUniversalTime() } elseif ($t) { [datetime]::Parse([string]$t, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal') } else { $null }
    }
    $peakAt = {
        param([object[]] $Series, [string] $Name, [string] $Field, [switch] $Low)
        $best = $null; $value = $null
        foreach ($s in $Series) { if (-not $Name -or $s.Name -eq $Name) { foreach ($pt in $s.Points) { $v = $pt[$Field]; if ($null -ne $v -and ($null -eq $value -or ($Low -and $v -lt $value) -or (-not $Low -and $v -gt $value))) { $value = $v; $best = $pt } } } }
        $t = & $timeOf $best
        if ($t) { @{ First = $t; Last = $t; Kind = 'peak' } } else { $null }
    }
    $window = {
        param([object[]] $Series, [string] $Name, [string] $Field, [scriptblock] $Match)
        $times = @(@(foreach ($s in $Series) { if (-not $Name -or $s.Name -eq $Name) { foreach ($pt in $s.Points) { $v = $pt[$Field]; if ($null -ne $v -and (& $Match ([double]$v))) { & $timeOf $pt } } } }) | Where-Object { $_ } | Sort-Object)
        if ($times.Count) { @{ First = $times[0]; Last = $times[-1]; Kind = 'window' } } else { $null }
    }
    $sinceOf = { param([string] $Id) $h = $health[$Id]; if ($h -and $h['since']) { $t = & $timeOf @{ timeStamp = $h['since'] }; if ($t) { @{ First = $t; Last = $null; Kind = 'since' } } } }
    $describe = {
        param($When)
        if (-not $When) { return '' }
        $f = { param([datetime] $D) $D.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture) }
        switch ($When.Kind) {
            'peak' { "peak at $(& $f $When.First) UTC" }
            'since' { "since $(& $f $When.First) UTC" }
            default { if ($When.First -eq $When.Last) { "at $(& $f $When.First) UTC" } elseif ($When.First.Date -eq $When.Last.Date) { "$(& $f $When.First) to $($When.Last.ToString('HH:mm')) UTC" } else { "$(& $f $When.First) to $(& $f $When.Last) UTC" } }
        }
    }
    $pct = { param($Value, $Limit) if ($null -eq $Value -or -not $Limit) { $null } else { [Math]::Round(100.0 * [double]$Value / [double]$Limit, 1) } }
    $skuBase = { param([string] $Sku) ($Sku -replace 'AZ$', '') }
    $vpnMbps = @{ Basic = 100; VpnGw1 = 650; VpnGw2 = 1000; VpnGw3 = 1250; VpnGw4 = 5000; VpnGw5 = 10000 }
    $vpnMbpsGen2 = @{ VpnGw2 = 1250; VpnGw3 = 2500; VpnGw4 = 5000; VpnGw5 = 10000 }
    $p2sMax = @{ Basic = 128; VpnGw1 = 250; VpnGw2 = 500; VpnGw3 = 1000; VpnGw4 = 5000; VpnGw5 = 10000 }
    $erPps = @{ Standard = 100000; ErGw1 = 100000; HighPerformance = 250000; ErGw2 = 250000; UltraPerformance = 1000000; ErGw3 = 1000000 }
    $firewallGbps = @{ Basic = 0.25; Standard = 30; Premium = 100 }
    $health = @{}
    foreach ($h in & $rows 'health') { $health[[string]$h['target']] = $h }

    $components = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param($Row, [string] $Component, [hashtable] $Signals, [string] $Sku, [string] $Capacity, [string] $State, [object[]] $Found, [string] $Detail)
        $id = [string]$Row['id']
        $h = $health[$id]
        $healthState = if ($h) { [string]$h['state'] } else { '' }
        foreach ($f in $Found) {
            $when = if ($f.Count -gt 5) { $f[5] } else { $null }
            $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.NetworkHealthFinding'; Severity = $f[0]; Component = $Component; Name = [string]$Row['name']; Signal = $f[1]; Finding = $f[2]; Detail = $f[3]; When = & $describe $when; FirstSeen = $(if ($when) { $when.First }); LastSeen = $(if ($when) { $when.Last }); Recommendation = $f[4]; ResourceGroup = [string]$Row['resourceGroup']; Subscription = & $subName ([string]$Row['subscriptionId']); ResourceId = $id })
        }
        $since = & $sinceOf $id
        if ($healthState -eq 'Unavailable') { $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.NetworkHealthFinding'; Severity = 'High'; Component = $Component; Name = [string]$Row['name']; Signal = 'Health'; Finding = 'Resource Health: Unavailable'; Detail = "$($h['summary'])$(if ($h['reason']) { " ($($h['reason']))" })"; When = & $describe $since; FirstSeen = $(if ($since) { $since.First }); LastSeen = $null; Recommendation = 'Open Resource Health for the cause and any Azure incident; fail over to the redundant path.'; ResourceGroup = [string]$Row['resourceGroup']; Subscription = & $subName ([string]$Row['subscriptionId']); ResourceId = $id }) }
        elseif ($healthState -eq 'Degraded') { $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.NetworkHealthFinding'; Severity = 'Medium'; Component = $Component; Name = [string]$Row['name']; Signal = 'Health'; Finding = 'Resource Health: Degraded'; Detail = [string]$h['summary']; When = & $describe $since; FirstSeen = $(if ($since) { $since.First }); LastSeen = $null; Recommendation = 'Check Resource Health and Service Health for the cause.'; ResourceGroup = [string]$Row['resourceGroup']; Subscription = & $subName ([string]$Row['subscriptionId']); ResourceId = $id }) }
        $healthScore = switch ($healthState) { 'Available' { 100 } 'Degraded' { 50 } 'Unavailable' { 0 } default { $null } }
        if ($Signals.Contains('Provisioned') -and $Signals.Provisioned -eq $false) { $healthScore = 0 }
        $band = { param($Used) if ($null -eq $Used) { $null } else { [Math]::Max(0, [Math]::Min(100, 100 - [Math]::Max(0, [double]$Used - 50) * 2)) } }
        $cells = [ordered]@{
            Availability = $(if ($null -ne $Signals.Availability) { [Math]::Max(0, [Math]::Min(100, ([double]$Signals.Availability - 99) * 100)) } else { $null })
            Utilization  = & $band $Signals.Utilization
            Drops        = $(if ($null -eq $Signals.Drops) { $null } elseif ([double]$Signals.Drops -le 0) { 100 } else { 40 })
            Capacity     = & $band $Signals.Capacity
            Health       = $healthScore
        }
        $scored = @($cells.Values | Where-Object { $null -ne $_ })
        $score = if ($scored.Count) { [Math]::Round(($scored | Measure-Object -Average).Average, 1) } else { $null }
        $components.Add([pscustomobject][ordered]@{
                PSTypeName       = 'AAC.NetworkHealth'
                Component        = $Component
                Name             = [string]$Row['name']
                Score            = $score
                Availability     = & $round $Signals.Availability 3
                PeakUtilization  = & $round $Signals.Utilization
                Drops            = & $round $Signals.Drops 2
                CapacityUsed     = & $round $Signals.Capacity
                Health           = $healthState
                HealthSince      = $(if ($since) { $since.First })
                PeakAt           = $(if ($Signals.Contains('PeakAt') -and $Signals.PeakAt) { $Signals.PeakAt.First })
                State            = $State
                Sku              = $Sku
                Capacity         = $Capacity
                Detail           = $Detail
                Findings         = @($Found).Count + $(if ($healthState -in 'Unavailable', 'Degraded') { 1 } else { 0 })
                Location         = [string]$Row['location']
                ResourceGroup    = [string]$Row['resourceGroup']
                Subscription     = & $subName ([string]$Row['subscriptionId'])
                ResourceId       = $id
                HeatCells        = $cells
            })
    }
    $warn = [double]$WarnPercent

    # --- ExpressRoute circuits --------------------------------------------------------------------------------
    foreach ($c in & $rows 'circuits') {
        $id = [string]$c['id']; $p = $c['properties']
        $bandwidth = [double]$(if (& $at $p 'serviceProviderProperties', 'bandwidthInMbps') { & $at $p 'serviceProviderProperties', 'bandwidthInMbps' } elseif (& $at $p 'bandwidthInGbps') { [double](& $at $p 'bandwidthInGbps') * 1000 } else { 0 })
        $provider = [string](& $at $p 'serviceProviderProvisioningState')
        $circuitState = [string](& $at $p 'circuitProvisioningState')
        $found = [System.Collections.Generic.List[object]]::new()
        $bgpSeries = & $seriesOf $id 'bgp'
        $availability = $null
        foreach ($name in 'BgpAvailability', 'ArpAvailability') {
            foreach ($s in @($bgpSeries | Where-Object { $_.Name -eq $name })) {
                $avg = & $mean (& $values @($s) $name 'average')
                if ($null -eq $avg) { continue }
                if ($null -eq $availability -or $avg -lt $availability) { $availability = $avg }
                if ($avg -lt 100) { $found.Add(@('High', 'Availability', "$($name -replace 'Availability', '') availability below 100%", ('{0} {1:N2}% on {2} peering, {3}.' -f ($name -replace 'Availability', ''), $avg, $s.Dims['peeringtype'], $s.Dims['peer']), 'Check the BGP session and ARP on that peering and link with your provider; traffic is on one link while the other is down.', (& $window @($s) $name 'average' { param($v) $v -lt 100 }))) }
            }
        }
        $bits = & $seriesOf $id 'bits'
        $peak = $null; $roleTotal = @{}
        foreach ($s in $bits) {
            $role = [string]$s.Dims['devicerole']
            $peakHere = & $max (& $values @($s) $s.Name 'maximum')
            if ($null -ne $peakHere -and ($null -eq $peak -or $peakHere -gt $peak)) { $peak = $peakHere }
            $roleTotal[$role] = [double]$(if ($roleTotal.Contains($role)) { $roleTotal[$role] } else { 0 }) + (& $sum (& $values @($s) $s.Name 'average'))
        }
        $utilization = if ($bandwidth) { & $pct $peak ($bandwidth * 1e6) } else { $null }
        if ($null -ne $utilization -and $utilization -ge $warn) { $found.Add(@($(if ($utilization -ge 95) { 'High' } else { 'Medium' }), 'Utilization', "Link at $([int]$utilization)% of bandwidth", ('Peak {0:N0} Mbps on a {1:N0} Mbps circuit.' -f ($peak / 1e6), $bandwidth), 'Upgrade the circuit bandwidth (no downtime on most providers), or add a second circuit.', (& $peakAt $bits '' 'maximum'))) }
        $totalBits = & $sum @($roleTotal.Values)
        if ($totalBits -gt 0 -and $roleTotal.Count) {
            $top = ($roleTotal.Values | Measure-Object -Maximum).Maximum
            if ($top / $totalBits -ge 0.95 -and ($totalBits / [Math]::Max(1, @($bits | ForEach-Object { $_.Points.Count } | Measure-Object -Maximum).Maximum)) -gt 1e6) { $found.Add(@('Medium', 'Availability', 'Traffic on one link', ('{0:N0}% of the traffic uses one link: the other carries none, so it isn''t proven, and a failure moves everything at once.' -f (100 * $top / $totalBits)), 'Check BGP on both links (AS path prepending or weights may pin traffic to one); run active-active.', $null)) }
        }
        elseif ((& $readOk $id 'bits') -and $provider -eq 'Provisioned') { $found.Add(@('Low', 'Utilization', 'No traffic in the period', 'The circuit carried nothing.', 'Confirm it is still needed - a circuit is billed whether used or not.', $null)) }
        $qos = & $seriesOf $id 'qos'
        $drops = if (& $readOk $id 'qos') { & $max (@(& $values $qos 'QosDropBitsInPerSecond' 'maximum') + @(& $values $qos 'QosDropBitsOutPerSecond' 'maximum')) } else { $null }
        if ($drops -gt 0) { $found.Add(@('Medium', 'Drops', 'Packets dropped (QoS)', ('Up to {0:N0} bits/s dropped.' -f $drops), 'Traffic exceeds the circuit or a QoS class: check DSCP markings and the bandwidth.', (& $peakAt $qos '' 'maximum'))) }
        if ($provider -ne 'Provisioned') { $found.Add(@('High', 'Health', 'Circuit not provisioned by the provider', "Provider state: $provider.", 'Complete provisioning with your connectivity provider (give them the service key).', $null)) }
        if ($circuitState -and $circuitState -ne 'Enabled') { $found.Add(@('High', 'Health', 'Circuit not enabled', "Circuit state: $circuitState.", 'Contact Microsoft support.', $null)) }
        $sku = "$(& $at $c 'sku', 'tier') $(& $at $c 'sku', 'family')".Trim()
        & $add $c 'ExpressRoute circuit' @{ Availability = $availability; Utilization = $utilization; Drops = $drops; Capacity = $null; Provisioned = ($provider -eq 'Provisioned'); PeakAt = (& $peakAt $bits '' 'maximum') } $sku "$bandwidth Mbps" "$provider / $circuitState" $found.ToArray() "$(& $at $p 'serviceProviderProperties', 'serviceProviderName') $(& $at $p 'serviceProviderProperties', 'peeringLocation') · $(@(& $at $p 'peerings').Count) peering(s)"
    }

    # --- Gateways -----------------------------------------------------------------------------------------------
    $connections = @(& $rows 'connections')
    foreach ($g in & $rows 'gateways') {
        $id = [string]$g['id']; $p = $g['properties']; $type = [string]$g['type']
        $found = [System.Collections.Generic.List[object]]::new()
        $sku = if (& $at $p 'sku', 'name') { [string](& $at $p 'sku', 'name') } else { '' }
        $vnet = $type -eq 'microsoft.network/virtualnetworkgateways'
        $isEr = $type -eq 'microsoft.network/expressroutegateways' -or ($vnet -and [string](& $at $p 'gatewayType') -eq 'ExpressRoute')
        $isP2s = $type -eq 'microsoft.network/p2svpngateways'
        $state = [string](& $at $p 'provisioningState')
        if ($isEr) {
            $perf = & $seriesOf $id 'perf'
            $cpu = & $max (& $values $perf 'ExpressRouteGatewayCpuUtilization' 'maximum')
            $pps = & $max (& $values $perf 'ExpressRouteGatewayPacketsPerSecond' 'maximum')
            $ppsLimit = if ($vnet) { $erPps[(& $skuBase $sku)] } else { $null }
            $routes = & $seriesOf $id 'routes'
            $advertised = & $max (& $values $routes 'ExpressRouteGatewayCountOfRoutesAdvertisedToPeer' 'maximum')
            $learned = & $max (& $values $routes 'ExpressRouteGatewayCountOfRoutesLearnedFromPeer' 'maximum')
            $capacity = & $max @($cpu, (& $pct $pps $ppsLimit), (& $pct $advertised 1000), (& $pct $learned 4000))
            if ($cpu -ge $warn) { $found.Add(@($(if ($cpu -ge 95) { 'High' } else { 'Medium' }), 'Capacity', "Gateway CPU at $([int]$cpu)%", 'CPU is per gateway, not per instance: near 100% it drops packets.', 'Scale the gateway up (ErGw2AZ, ErGw3AZ or scale units) or enable FastPath.', (& $peakAt $perf 'ExpressRouteGatewayCpuUtilization' 'maximum'))) }
            if ($ppsLimit -and (& $pct $pps $ppsLimit) -ge $warn) { $found.Add(@('Medium', 'Capacity', 'Packets per second near the SKU limit', ('Peak {0:N0} pps of about {1:N0}.' -f $pps, $ppsLimit), 'Scale the gateway up, or use FastPath to bypass it.', (& $peakAt $perf 'ExpressRouteGatewayPacketsPerSecond' 'maximum'))) }
            foreach ($r in @(@('advertised to', $advertised, 1000), @('learned from', $learned, 4000))) {
                $used = & $pct $r[1] $r[2]
                if ($used -ge 75) { $found.Add(@($(if ($used -ge 90) { 'High' } else { 'Medium' }), 'Capacity', "Routes $($r[0]) the peer near the limit", ('{0:N0} of {1:N0} routes - past the limit, BGP drops the session.' -f $r[1], $r[2]), 'Summarise the prefixes (on-premises, or the VNet address spaces).', (& $peakAt $routes $(if ($r[0] -eq 'advertised to') { 'ExpressRouteGatewayCountOfRoutesAdvertisedToPeer' } else { 'ExpressRouteGatewayCountOfRoutesLearnedFromPeer' }) 'maximum'))) }
            }
            if ($vnet -and $sku -notmatch 'AZ$|ErGwScale') { $found.Add(@('Medium', 'Health', 'Gateway not zone-redundant', "SKU $sku.", 'Migrate to a zone-redundant SKU (ErGw1AZ or higher, or ErGwScale).', $null)) }
            & $add $g 'ExpressRoute gateway' @{ Availability = $null; Utilization = $null; Drops = $null; Capacity = $capacity; PeakAt = (& $peakAt $perf 'ExpressRouteGatewayCpuUtilization' 'maximum') } $(if ($sku) { $sku } else { "$(& $at $p 'autoScaleConfiguration', 'bounds', 'min') scale unit(s)" }) $(if ($ppsLimit) { "~$('{0:N0}' -f $ppsLimit) pps" } else { '' }) $state $found.ToArray() ('CPU {0} · {1} pps · routes {2} out / {3} in' -f $(if ($null -ne $cpu) { "$([int]$cpu)%" } else { '-' }), $(if ($null -ne $pps) { '{0:N0}' -f $pps } else { '-' }), $(if ($null -ne $advertised) { [int]$advertised } else { '-' }), $(if ($null -ne $learned) { [int]$learned } else { '-' }))
            continue
        }
        # VPN and point-to-site gateways.
        $base = & $skuBase $sku
        $generation2 = [string](& $at $p 'vpnGatewayGeneration') -eq 'Generation2'
        $limitMbps = if ($generation2 -and $vpnMbpsGen2.Contains($base)) { $vpnMbpsGen2[$base] } elseif ($vpnMbps.Contains($base)) { $vpnMbps[$base] } elseif (& $at $p 'vpnGatewayScaleUnit') { 500 * [int](& $at $p 'vpnGatewayScaleUnit') } else { $null }
        $bw = & $max (& $values (& $seriesOf $id 'bw') 'AverageBandwidth' 'maximum')
        $utilization = if ($limitMbps -and $null -ne $bw) { & $pct ($bw * 8 / 1e6) $limitMbps } else { $null }
        $bgpSeries = & $seriesOf $id 'bgp'
        $availability = $null
        foreach ($s in $bgpSeries) {
            $avg = & $mean (& $values @($s) 'BgpPeerStatus' 'average')
            if ($null -eq $avg) { continue }
            $asPct = 100 * $avg
            if ($null -eq $availability -or $asPct -lt $availability) { $availability = $asPct }
            if ($avg -le 0) { $found.Add(@('High', 'Availability', 'BGP peer down', "Peer $($s.Dims['bgppeeraddress']) never connected in the period.", 'Check the peer''s ASN and address, the tunnel, and BGP on the on-premises device.', (& $window @($s) 'BgpPeerStatus' 'average' { param($v) $v -lt 1 }))) }
            elseif ($avg -lt 0.99) { $found.Add(@('Medium', 'Availability', 'BGP peer flapping', ('Peer {0} was up {1:N1}% of the period.' -f $s.Dims['bgppeeraddress'], $asPct), 'Look for tunnel drops (DPD, rekey) and the on-premises device''s logs.', (& $window @($s) 'BgpPeerStatus' 'average' { param($v) $v -lt 1 }))) }
        }
        $p2s = & $max (& $values (& $seriesOf $id 'p2s') 'P2SConnectionCount' 'maximum')
        $p2sLimit = if ($p2sMax.Contains($base)) { $p2sMax[$base] } else { $null }
        $capacity = & $pct $p2s $p2sLimit
        if ($null -ne $utilization -and $utilization -ge $warn) { $found.Add(@($(if ($utilization -ge 95) { 'High' } else { 'Medium' }), 'Utilization', "Gateway bandwidth at $([int]$utilization)% of the SKU", ('Peak {0:N0} Mbps of about {1:N0}.' -f ($bw * 8 / 1e6), $limitMbps), 'Resize to a larger SKU, or spread tunnels over gateways.', (& $peakAt (& $seriesOf $id 'bw') 'AverageBandwidth' 'maximum'))) }
        if ($null -ne $capacity -and $capacity -ge $warn) { $found.Add(@('Medium', 'Capacity', 'Point-to-site connections near the SKU limit', ('{0:N0} of {1:N0}.' -f $p2s, $p2sLimit), 'Resize to a larger SKU.', (& $peakAt (& $seriesOf $id 'p2s') 'P2SConnectionCount' 'maximum'))) }
        $tunnelDrops = 0.0
        foreach ($s in @(& $seriesOf $id 'tunnels' | Where-Object { $_.Name -like 'Tunnel*PacketDropCount' })) { $tunnelDrops += & $sum (& $values @($s) $s.Name 'total') }
        if ($vnet -and -not $isP2s) {
            if ((& $at $p 'activeActive') -ne $true) { $found.Add(@('Medium', 'Availability', 'VPN gateway not active-active', 'One instance carries the tunnels: maintenance or a failure drops them for a minute or more.', 'Turn on active-active, with two tunnels from each on-premises device.', $null)) }
            if ($base -eq 'Basic') { $found.Add(@('Low', 'Health', 'Basic VPN SKU', 'Basic has no BGP, no active-active and no zone redundancy.', 'Move to VpnGw1AZ or higher.', $null)) }
            elseif ($sku -notmatch 'AZ$') { $found.Add(@('Low', 'Health', 'Gateway not zone-redundant', "SKU $sku.", 'Move to the AZ SKU of the same size.', $null)) }
        }
        & $add $g $(if ($isP2s) { 'Point-to-site gateway' } else { 'VPN gateway' }) @{ Availability = $availability; Utilization = $utilization; Drops = $(if (& $readOk $id 'tunnels') { $tunnelDrops } else { $null }); Capacity = $capacity; PeakAt = (& $peakAt (& $seriesOf $id 'bw') 'AverageBandwidth' 'maximum') } $sku $(if ($limitMbps) { "~$limitMbps Mbps" } else { '' }) $state $found.ToArray() ('{0} Mbps peak{1}{2}' -f $(if ($null -ne $bw) { '{0:N0}' -f ($bw * 8 / 1e6) } else { '-' }), $(if ($null -ne $p2s) { " · $([int]$p2s) P2S user(s)" }), $(if ((& $at $p 'activeActive') -eq $true) { ' · active-active' }))
    }

    # --- Connections: their state, and their tunnel's traffic and drops ------------------------------------------
    foreach ($cn in $connections) {
        $p = $cn['properties']
        $found = [System.Collections.Generic.List[object]]::new()
        $status = [string](& $at $p 'connectionStatus')
        $kind = [string](& $at $p 'connectionType')
        $gateway = ([string](& $at $p 'virtualNetworkGateway1', 'id')).ToLowerInvariant()
        $tunnel = @(& $seriesOf $gateway 'tunnels' | Where-Object { $_.Dims['connectionname'] -eq [string]$cn['name'] })
        $drops = if ($tunnel.Count) { & $sum @(foreach ($s in @($tunnel | Where-Object { $_.Name -like 'Tunnel*PacketDropCount' })) { & $sum (& $values @($s) $s.Name 'total') }) } else { $null }
        $peakBytes = & $max (& $values $tunnel 'TunnelAverageBandwidth' 'maximum')
        if ($status -and $status -ne 'Connected') { $found.Add(@('High', 'Availability', 'Connection not connected', "Status: $status.", $(if ($kind -eq 'ExpressRoute') { 'Check the circuit is provisioned and the private peering configured; check the authorization key.' } else { 'Check the shared key, IKE/IPsec settings and the on-premises device; Resource Health and the gateway''s diagnostics logs give the reason.' }), (& $sinceOf ([string]$cn['id'])))) }
        if ($drops -gt 0) { $found.Add(@('Medium', 'Drops', 'Tunnel packets dropped', ('{0:N0} packet(s) dropped in the period.' -f $drops), 'Check MTU/MSS clamping, the traffic selectors and the on-premises device''s policy.', (& $window @($tunnel | Where-Object { $_.Name -like 'Tunnel*PacketDropCount' }) '' 'total' { param($v) $v -gt 0 }))) }
        if ($kind -eq 'IPsec' -and (& $at $p 'enableBgp') -ne $true) { $found.Add(@('Low', 'Availability', 'Static routing (no BGP)', 'Routes don''t fail over between tunnels by themselves.', 'Use BGP where the on-premises device supports it.', $null)) }
        & $add $cn "$(if ($kind) { $kind } else { 'Connection' }) connection" @{ Availability = $(if ($status -eq 'Connected') { 100 } elseif ($status) { 0 } else { $null }); Utilization = $null; Drops = $drops; Capacity = $null } '' '' $status $found.ToArray() ('{0}{1}' -f "gateway $(($gateway -split '/')[-1])", $(if ($null -ne $peakBytes) { ' · peak {0:N1} Mbps' -f ($peakBytes * 8 / 1e6) }))
    }

    # --- Azure Firewalls ------------------------------------------------------------------------------------------
    foreach ($f in & $rows 'firewalls') {
        $id = [string]$f['id']; $p = $f['properties']
        $found = [System.Collections.Generic.List[object]]::new()
        $fw = & $seriesOf $id 'fw'
        $tier = [string](& $at $p 'sku', 'tier')
        $healthPct = & $min (& $values $fw 'FirewallHealth' 'minimum')
        if ($null -eq $healthPct) { $healthPct = & $min (& $values $fw 'FirewallHealth' 'average') }
        $snat = & $max (& $values $fw 'SNATPortUtilization' 'maximum')
        $throughput = & $max (& $values $fw 'Throughput' 'maximum')
        $limit = if ($firewallGbps.Contains($tier)) { $firewallGbps[$tier] * 1e9 } else { $null }
        $utilization = & $pct $throughput $limit
        $latency = & $max (& $values (& $seriesOf $id 'latency') 'FirewallLatencyPng' 'average')
        if ($null -ne $healthPct -and $healthPct -lt 100) { $found.Add(@($(if ($healthPct -lt 90) { 'High' } else { 'Medium' }), 'Availability', 'Firewall health below 100%', ('Lowest {0:N1}% - usually SNAT port exhaustion or a data path issue.' -f $healthPct), 'Check SNAT utilisation; add public IPs or a NAT gateway; open Resource Health.', (& $window $fw 'FirewallHealth' 'minimum' { param($v) $v -lt 100 }))) }
        if ($snat -ge $warn) { $found.Add(@($(if ($snat -ge 95) { 'High' } else { 'Medium' }), 'Capacity', "SNAT ports at $([int]$snat)%", 'At 100% new outbound connections fail.', 'Associate a NAT gateway with the firewall subnet, or add public IPs.', (& $peakAt $fw 'SNATPortUtilization' 'maximum'))) }
        if ($null -ne $utilization -and $utilization -ge $warn) { $found.Add(@('Medium', 'Utilization', "Throughput at $([int]$utilization)% of the tier", ('Peak {0:N1} Gbps of {1} Gbps ({2}).' -f ($throughput / 1e9), ($limit / 1e9), $tier), 'Move to a higher tier (Premium scales to 100 Gbps), or split the traffic.', (& $peakAt $fw 'Throughput' 'maximum'))) }
        if ($latency -gt 20) { $found.Add(@('Low', 'Utilization', 'Firewall latency high', ('Up to {0:N1} ms average latency.' -f $latency), 'Expect it under heavy load or IDPS; check throughput and the rule count.', (& $peakAt (& $seriesOf $id 'latency') 'FirewallLatencyPng' 'average'))) }
        if (-not @(& $at $f 'zones' | Where-Object { $_ }).Count) { $found.Add(@('Medium', 'Availability', 'Firewall not zone-redundant', 'Without zones the SLA is 99.95% and a zone failure stops it.', 'Deploy across availability zones (redeploy, or use the zone-redundancy migration).', $null)) }
        & $add $f 'Azure Firewall' @{ Availability = $healthPct; Utilization = $utilization; Drops = $null; Capacity = $snat; PeakAt = (& $peakAt $fw 'Throughput' 'maximum') } "$tier" $(if ($limit) { "$($limit / 1e9) Gbps" } else { '' }) ([string](& $at $p 'provisioningState')) $found.ToArray() ('SNAT {0} · {1} Gbps peak · {2} public IP(s)' -f $(if ($null -ne $snat) { "$([int]$snat)%" } else { '-' }), $(if ($null -ne $throughput) { '{0:N2}' -f ($throughput / 1e9) } else { '-' }), @(& $at $p 'ipConfigurations' | Where-Object { $_ }).Count)
    }

    # --- NAT gateways --------------------------------------------------------------------------------------------
    foreach ($n in & $rows 'natgateways') {
        $id = [string]$n['id']; $p = $n['properties']
        $found = [System.Collections.Generic.List[object]]::new()
        $nat = & $seriesOf $id 'nat'
        $path = & $min (& $values $nat 'DatapathAvailability' 'average')
        $dropped = if (& $readOk $id 'nat') { & $sum (& $values $nat 'PacketDropCount' 'total') } else { $null }
        $snat = & $max (& $values $nat 'SNATConnectionCount' 'maximum')
        $ips = @(& $at $p 'publicIpAddresses' | Where-Object { $_ }).Count
        $prefixes = @(& $at $p 'publicIpPrefixes' | Where-Object { $_ }).Count
        $capacity = if ($ips -and -not $prefixes) { & $pct $snat (64512 * $ips) } else { $null }
        if ($null -ne $path -and $path -lt 99.9) { $found.Add(@('High', 'Availability', 'NAT data path availability low', ('Lowest {0:N2}%.' -f $path), 'Open Resource Health; check SNAT exhaustion and the connections per destination.', (& $window $nat 'DatapathAvailability' 'average' { param($v) $v -lt 99.9 }))) }
        if ($dropped -gt 0) { $found.Add(@('Medium', 'Drops', 'NAT gateway dropped packets', ('{0:N0} packet(s) dropped.' -f $dropped), 'Usually SNAT exhaustion to one destination: add public IPs, reuse connections, shorten the idle timeout.', (& $window $nat 'PacketDropCount' 'total' { param($v) $v -gt 0 }))) }
        if ($null -ne $capacity -and $capacity -ge $warn) { $found.Add(@('Medium', 'Capacity', "SNAT connections at $([int]$capacity)% of capacity", ('{0:N0} of {1:N0} ({2} public IP(s)).' -f $snat, (64512 * $ips), $ips), 'Add public IPs or a prefix.', (& $peakAt $nat 'SNATConnectionCount' 'maximum'))) }
        if (-not @(& $at $p 'subnets' | Where-Object { $_ }).Count) { $found.Add(@('Low', 'Utilization', 'NAT gateway on no subnet', 'It is billed and does nothing.', 'Associate it with the subnets that need outbound access, or delete it.', $null)) }
        & $add $n 'NAT gateway' @{ Availability = $path; Utilization = $null; Drops = $dropped; Capacity = $capacity; PeakAt = (& $peakAt $nat 'SNATConnectionCount' 'maximum') } ([string](& $at $n 'sku', 'name')) $(if ($ips) { "$ips IP(s) x 64,512 ports" } else { '' }) ([string](& $at $p 'provisioningState')) $found.ToArray() ('{0} subnet(s) · {1} IP(s) · {2} prefix(es)' -f @(& $at $p 'subnets' | Where-Object { $_ }).Count, $ips, $prefixes)
    }

    # --- Heat map, findings, stats --------------------------------------------------------------------------------
    $signals = @('Availability', 'Utilization', 'Drops', 'Capacity', 'Health')
    $ordered = @($components | Sort-Object -Property @{ Expression = { if ($null -eq $_.Score) { 101 } else { $_.Score } } }, Component, Name)
    $heatRows = @(foreach ($c in @($ordered | Select-Object -First 40)) {
            @{ Label = "$($c.Name) ($($c.Component))"; Filter = $c.Name; Cells = @(foreach ($s in $signals) { if ($null -ne $c.HeatCells[$s]) { @{ Score = [Math]::Round([double]$c.HeatCells[$s], 1) } } else { $null } }); Total = $(if ($null -ne $c.Score) { @{ Score = $c.Score } } else { $null }) }
        })
    $rank = @{ High = 0; Medium = 1; Low = 2 }
    $list = @($ordered | Select-Object -Property * -ExcludeProperty HeatCells | ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'AAC.NetworkHealth'); $_ })
    @{
        Components = $list
        Findings   = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Component, Name)
        HeatMap    = @{ Title = 'Network components by signal'; RowHeader = 'Component'; Columns = $signals; Rows = $heatRows; Table = 'findings'; RowKey = 'Name'; ColumnKey = 'Signal'
            Note = "0-100 per signal, worst first$(if ($components.Count -gt 40) { " (40 of $($components.Count))" }): availability (BGP, ARP, health, data path), utilisation of capacity, drops, capacity limits (CPU, routes, SNAT, P2S), Resource Health." }
        Stats      = @{
            Components = $components.Count
            Circuits   = @($components | Where-Object Component -EQ 'ExpressRoute circuit').Count
            Gateways   = @($components | Where-Object { $_.Component -like '*gateway' -and $_.Component -ne 'NAT gateway' }).Count
            Connections = @($components | Where-Object { $_.Component -like '*connection' }).Count
            Firewalls  = @($components | Where-Object Component -EQ 'Azure Firewall').Count
            NatGateways = @($components | Where-Object Component -EQ 'NAT gateway').Count
            High       = @($findings | Where-Object Severity -EQ 'High').Count
            Findings   = $findings.Count
            Down       = @($findings | Where-Object { $_.Finding -in 'Connection not connected', 'BGP peer down', 'Resource Health: Unavailable' }).Count
        }
    }
}
