function ConvertTo-AACLoadBalancerHealth {
    <#
    .SYNOPSIS
        Builds Get-AACLoadBalancerHealth's model from the Resource Graph rows
        of Get-AACLoadBalancerQuery and the Azure Monitor metrics read for
        each balancer: every backend's health, each balancer's state, and
        the findings.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result. -Metric maps
        a balancer ID (lower case) to @{ Dip; Vip; Hosts; Error } - the
        metrics responses (as ARM returns them) for a load balancer's
        health probe status (DipAvailability, by backend IP) and data path
        availability (VipAvailability), and an Application Gateway's healthy
        and unhealthy host counts (by pool and settings). A balancer missing
        from -Metric wasn't measured.

        Backends (AAC.LoadBalancerBackend): a load balancer's backend IPs
        (named after their VM where the NIC is known) with their probe
        availability; an Application Gateway's pools (per HTTP settings)
        with their healthy and unhealthy hosts; a Traffic Manager profile's
        endpoints with their monitor status. Health: Unhealthy, Partial,
        Unknown, Not measured, Disabled, Healthy.

        Balancers (AAC.LoadBalancer) and findings (AAC.LoadBalancerFinding):
        backends down (all of a pool: High; some: Medium), data path below
        100%, retired SKUs (Basic load balancer, Application Gateway v1),
        rules without a health probe, empty pools, a single backend or one
        gateway instance (no redundancy), Traffic Manager endpoints degraded
        or profiles disabled.

        Returns @{ Backends; Balancers; Findings; Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Metric = @{},

        [hashtable] $SubscriptionName = @{}
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $list = { param($Item) @(if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string] -and $Item -isnot [System.Collections.IDictionary]) { $Item } elseif ($null -ne $Item) { , $Item }) | Where-Object { $null -ne $_ -and '' -ne $_ } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ -and $SubscriptionName.Contains(([string]$_['subscriptionId']).ToLowerInvariant()) } }) }
    $label = { param([string] $Id) $s = ([string]$Id).ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { $SubscriptionName[$s] } else { $Id } }
    $leaf = { param([string] $Id) if ($Id) { ($Id.TrimEnd('/') -split '/')[-1] } else { '' } }
    # A metrics response -> dimension value (or '' for none) -> the latest average.
    $latest = {
        param($Body, [string] $Name, [string] $Dimension)
        $out = @{}
        foreach ($m in @(& $list (& $get $Body 'value'))) {
            if ((& $text $m 'name.value') -ne $Name) { continue }
            foreach ($series in @(& $list (& $get $m 'timeseries'))) {
                $key = ''
                foreach ($d in @(& $list (& $get $series 'metadatavalues'))) { if ((& $text $d 'name.value') -eq $Dimension) { $key = & $text $d 'value' } }
                $points = @(@(& $list (& $get $series 'data')) | Where-Object { $null -ne (& $get $_ 'average') })
                if ($points.Count) { $out[$key] = [double](& $get $points[-1] 'average') }
            }
        }
        $out
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(@{ loadBalancers = 'load balancers'; appGateways = 'Application Gateways'; trafficManager = 'Traffic Manager profiles'; backendNics = 'backend NICs' }[$key]) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    $backends = [System.Collections.Generic.List[object]]::new()
    $balancers = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $docs = 'https://learn.microsoft.com/azure'
    $finding = {
        param([string] $Severity, [string] $Category, [string] $Finding, $Row, [string] $Detail, [string] $Impact, [string] $Remediation, [string] $Link, [string] $Effort = 'Low')
        $findings.Add((New-AACFinding -TypeName 'AAC.LoadBalancerFinding' -Severity $Severity -Category $Category -Finding $Finding -ResourceId (& $text $Row 'id') -Resource (& $text $Row 'name') -ResourceGroup (& $text $Row 'resourceGroup') `
                    -Subscription (& $label (& $text $Row 'subscriptionId')) -Detail $Detail -Impact $Impact -Remediation $Remediation -Effort $Effort -Link $Link))
    }
    $backend = {
        param($Row, [string] $Kind, [string] $Pool, [string] $Name, [string] $Address, [string] $Health, $Availability, [string] $Probe, [string] $Detail)
        $item = [pscustomobject][ordered]@{
            Health        = $Health
            Balancer      = & $text $Row 'name'
            Kind          = $Kind
            Pool          = $Pool
            Backend       = $Name
            Address       = $Address
            Availability  = $Availability
            Probe         = $Probe
            Detail        = $Detail
            ResourceGroup = & $text $Row 'resourceGroup'
            Subscription  = & $label (& $text $Row 'subscriptionId')
            Location      = & $text $Row 'location'
            ResourceId    = & $text $Row 'id'
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.LoadBalancerBackend')
        $backends.Add($item)
        $item
    }
    $balancer = {
        param($Row, [string] $Kind, [string] $Sku, [string] $State, [int] $Pools, [object[]] $Members, $DataPath, [string] $Issues)
        $unhealthy = @($Members | Where-Object Health -EQ 'Unhealthy').Count
        $partial = @($Members | Where-Object Health -EQ 'Partial').Count
        $healthy = @($Members | Where-Object Health -EQ 'Healthy').Count
        $health = if ($State -eq 'Stopped' -or $State -eq 'Disabled') { 'Stopped' }
        elseif (($Members.Count -and $unhealthy -eq $Members.Count) -or ($null -ne $DataPath -and $DataPath -lt 90)) { 'Unhealthy' }
        elseif ($unhealthy -or $partial -or ($null -ne $DataPath -and $DataPath -lt 100)) { 'Degraded' }
        elseif ($healthy) { 'Healthy' }
        else { 'Unknown' }
        $item = [pscustomobject][ordered]@{
            Health        = $health
            Balancer      = & $text $Row 'name'
            Kind          = $Kind
            Sku           = $Sku
            State         = $State
            Pools         = $Pools
            Backends      = $Members.Count
            Healthy       = $healthy
            Unhealthy     = $unhealthy + $partial
            DataPath      = $DataPath
            Issues        = $Issues
            ResourceGroup = & $text $Row 'resourceGroup'
            Subscription  = & $label (& $text $Row 'subscriptionId')
            Location      = & $text $Row 'location'
            ResourceId    = & $text $Row 'id'
        }
        $item.PSObject.TypeNames.Insert(0, 'AAC.LoadBalancer')
        $balancers.Add($item)
    }
    $nics = @{}
    foreach ($row in @(if ($Read.Rows.Contains('backendNics')) { $Read.Rows['backendNics'] | Where-Object { $_ } })) { $nics[(& $text $row 'id')] = @{ Ip = (& $text $row 'ip'); Vm = (& $leaf (& $text $row 'vm')); Nic = (& $text $row 'nic') } }

    # --- Load balancers ---------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'loadBalancers')) {
        $id = & $text $row 'id'; $sku = & $text $row 'sku'
        $measured = $Metric.Contains($id) -and -not $Metric[$id].Error
        $probeOf = if ($measured -and $Metric[$id].Dip) { & $latest $Metric[$id].Dip 'DipAvailability' 'BackendIPAddress' } else { @{} }
        $vip = if ($measured -and $Metric[$id].Vip) { (& $latest $Metric[$id].Vip 'VipAvailability' '').Values | Select-Object -First 1 } else { $null }
        $dataPath = if ($null -ne $vip) { [Math]::Round([double]$vip, 1) } else { $null }
        $pools = @(& $list (& $get $row 'pools'))
        $probes = @(& $list (& $get $row 'probes'))
        $rules = @(& $list (& $get $row 'rules'))
        $members = [System.Collections.Generic.List[object]]::new()
        $seen = @{}
        $probeLabel = @{}
        foreach ($p in $probes) { $probeLabel[(& $text $p 'id').ToLowerInvariant()] = "$(& $text $p 'properties.protocol') $(& $text $p 'properties.port')$(if (& $text $p 'properties.requestPath') { " $(& $text $p 'properties.requestPath')" })" }
        foreach ($pool in $pools) {
            $poolName = & $text $pool 'name'
            $poolId = (& $text $pool 'id').ToLowerInvariant()
            $poolRules = @($rules | Where-Object { $r = $_; (& $text $r 'properties.backendAddressPool.id').ToLowerInvariant() -eq $poolId -or @(@(& $list (& $get $r 'properties.backendAddressPools')) | Where-Object { (& $text $_ 'id').ToLowerInvariant() -eq $poolId }).Count })
            $probeText = (@($poolRules | ForEach-Object { $probeLabel[(& $text $_ 'properties.probe.id').ToLowerInvariant()] } | Where-Object { $_ } | Select-Object -Unique) -join ', ')
            $addresses = @(@(& $list (& $get $pool 'properties.backendIPConfigurations')) | ForEach-Object {
                    $configId = (& $text $_ 'id').ToLowerInvariant()
                    if ($nics.Contains($configId)) { @{ Name = $(if ($nics[$configId].Vm) { $nics[$configId].Vm } else { $nics[$configId].Nic }); Ip = $nics[$configId].Ip } }
                    elseif ($configId -match '/virtualmachinescalesets/([^/]+)/virtualmachines/(\d+)/') { @{ Name = "$($Matches[1])_$($Matches[2])"; Ip = '' } }
                    else { @{ Name = (& $leaf ($configId -replace '/ipconfigurations/[^/]+$', '')); Ip = '' } }
                }) + @(@(& $list (& $get $pool 'properties.loadBalancerBackendAddresses')) | ForEach-Object { @{ Name = (& $text $_ 'name'); Ip = (& $text $_ 'properties.ipAddress') } })
            if (-not $addresses.Count) {
                & $finding 'Medium' 'Configuration' 'Empty backend pool' $row "Pool $poolName of $(& $text $row 'name') has no backends." 'Traffic sent to its rules has nowhere to go.' 'Add the backends, or remove the pool and its rules.' "$docs/load-balancer/backend-pool-management"
                continue
            }
            if ($addresses.Count -eq 1) {
                & $finding 'Low' 'Resilience' 'Backend pool with a single backend' $row "Pool $poolName of $(& $text $row 'name') has one backend ($($addresses[0].Name))." 'One backend down is the whole service down; maintenance means an outage.' 'Add a second backend, in another availability zone.' "$docs/load-balancer/load-balancer-overview" 'Medium'
            }
            foreach ($a in $addresses) {
                $availability = if ($a.Ip -and $probeOf.Contains($a.Ip)) { [Math]::Round($probeOf[$a.Ip], 1) } else { $null }
                if ($a.Ip) { $seen[$a.Ip] = $true }
                $health = if ($sku -eq 'Basic' -or -not $Metric.Contains($id)) { 'Not measured' } elseif (-not $measured) { 'Unknown' } elseif ($null -eq $availability) { 'Unknown' } elseif ($availability -ge 100) { 'Healthy' } elseif ($availability -le 0) { 'Unhealthy' } else { 'Partial' }
                $members.Add((& $backend $row 'Load balancer' $poolName $a.Name $a.Ip $health $availability $probeText $(switch ($health) { 'Unhealthy' { 'The health probe fails: no new flows are sent to it.' } 'Partial' { "The health probe passed $availability% of the time in the window: flapping." } 'Not measured' { $(if ($sku -eq 'Basic') { 'Basic load balancers have no health metrics.' } else { 'Metrics not read.' }) } default { '' } })))
            }
        }
        # Probed addresses the configuration doesn't name (scale set instances).
        foreach ($ip in @($probeOf.Keys | Where-Object { $_ -and -not $seen.Contains($_) } | Sort-Object)) {
            $availability = [Math]::Round($probeOf[$ip], 1)
            $members.Add((& $backend $row 'Load balancer' $(if ($pools.Count -eq 1) { & $text $pools[0] 'name' } else { '' }) $ip $ip $(if ($availability -ge 100) { 'Healthy' } elseif ($availability -le 0) { 'Unhealthy' } else { 'Partial' }) $availability '' ''))
        }
        $issues = [System.Collections.Generic.List[string]]::new()
        foreach ($group in @($members | Group-Object Pool)) {
            $down = @($group.Group | Where-Object { $_.Health -in 'Unhealthy', 'Partial' })
            if (-not $down.Count) { continue }
            $all = $down.Count -eq $group.Count -and @($group.Group | Where-Object Health -EQ 'Unhealthy').Count -eq $group.Count
            & $finding $(if ($all) { 'High' } else { 'Medium' }) 'Health' $(if ($all) { 'Every backend in the pool is down' } else { 'Backends failing their health probe' }) $row "Pool $($group.Name) of $(& $text $row 'name'): $(@($down | ForEach-Object { "$($_.Backend) ($($_.Availability)%)" }) -join ', ') of $($group.Count) backend(s)." $(if ($all) { 'The service behind this pool is down.' } else { 'Capacity is reduced; the remaining backends take the load.' }) 'Check the backends answer the probe (the app is running, the port open in the NSG and the OS firewall, the path returns 200).' "$docs/load-balancer/load-balancer-troubleshoot-health-probe-status" 'Medium'
            $issues.Add($(if ($all) { "pool $($group.Name) down" } else { "$($down.Count) backend(s) failing" }))
        }
        if ($null -ne $dataPath -and $dataPath -lt 100) {
            & $finding $(if ($dataPath -lt 90) { 'High' } else { 'Medium' }) 'Health' 'Data path availability below 100%' $row "$(& $text $row 'name')'s data path was $dataPath% available in the window." 'Some connections through the frontend fail - a platform problem, or the frontend misconfigured.' 'Check Resource Health and Service Health for the region; then the frontend IP and rules.' "$docs/load-balancer/load-balancer-standard-diagnostics"
            $issues.Add("data path $dataPath%")
        }
        if ($sku -eq 'Basic') {
            & $finding 'High' 'Retirement' 'Basic Load Balancer (retired)' $row "$(& $text $row 'name') is a Basic load balancer; Basic was retired on 30 September 2025." 'No SLA, no health metrics, no availability zones - and no support.' 'Upgrade to Standard (the upgrade script in the docs moves the configuration).' "$docs/load-balancer/load-balancer-basic-upgrade-guidance" 'Medium'
            $issues.Add('Basic SKU retired')
        }
        foreach ($rule in @($rules | Where-Object { -not (& $text $_ 'properties.probe.id') })) {
            & $finding 'Medium' 'Configuration' 'Load-balancing rule without a health probe' $row "Rule $(& $text $rule 'name') of $(& $text $row 'name') has no health probe." 'Traffic goes to backends whether or not they answer.' 'Add a health probe (HTTP to a health page, ideally) and attach it to the rule.' "$docs/load-balancer/load-balancer-custom-probe-overview"
        }
        & $balancer $row 'Load balancer' $sku '' $pools.Count $members.ToArray() $dataPath ($issues -join ', ')
    }

    # --- Application Gateways -------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'appGateways')) {
        $id = & $text $row 'id'; $tier = & $text $row 'tier'; $state = & $text $row 'state'
        $measured = $Metric.Contains($id) -and -not $Metric[$id].Error -and $Metric[$id].Hosts
        $healthyOf = if ($measured) { & $latest $Metric[$id].Hosts 'HealthyHostCount' 'BackendSettingsPool' } else { @{} }
        $unhealthyOf = if ($measured) { & $latest $Metric[$id].Hosts 'UnhealthyHostCount' 'BackendSettingsPool' } else { @{} }
        $pools = @(& $list (& $get $row 'pools'))
        $members = [System.Collections.Generic.List[object]]::new()
        $issues = [System.Collections.Generic.List[string]]::new()
        $v1 = $tier -in 'Standard', 'WAF'
        foreach ($pool in $pools) {
            $poolName = & $text $pool 'name'
            $count = @(@(& $list (& $get $pool 'properties.backendAddresses')) + @(& $list (& $get $pool 'properties.backendIPConfigurations'))).Count
            if (-not $count) {
                $members.Add((& $backend $row 'Application Gateway' $poolName '(empty)' '' 'Unhealthy' $null '' 'The pool has no backends: requests routed to it fail (502).'))
                & $finding 'High' 'Configuration' 'Empty backend pool' $row "Pool $poolName of $(& $text $row 'name') has no backends." 'Requests routed to it fail with 502 Bad Gateway.' 'Add the backends, or remove the pool and the rules that use it.' "$docs/application-gateway/application-gateway-backend-health-troubleshooting"
                continue
            }
            $keys = @($healthyOf.Keys + $unhealthyOf.Keys | Where-Object { $_ -like "$poolName~*" } | Select-Object -Unique)
            if (-not $keys.Count) { $members.Add((& $backend $row 'Application Gateway' $poolName "$count backend(s)" '' $(if ($state -eq 'Stopped') { 'Disabled' } elseif ($v1 -or -not $Metric.Contains($id)) { 'Not measured' } else { 'Unknown' }) $null '' $(if ($v1) { 'Application Gateway v1 has no host count metrics.' } else { '' }))); continue }
            foreach ($key in $keys) {
                $ok = [int][Math]::Round([double]$healthyOf[$key]); $bad = [int][Math]::Round([double]$unhealthyOf[$key])
                $settings = ($key -split '~', 2)[1]
                $health = if ($bad -and -not $ok) { 'Unhealthy' } elseif ($bad) { 'Partial' } elseif ($ok) { 'Healthy' } else { 'Unknown' }
                $members.Add((& $backend $row 'Application Gateway' $poolName "$count backend(s) via $settings" '' $health $(if ($ok + $bad) { [Math]::Round(100 * $ok / ($ok + $bad), 1) } else { $null }) $settings "$ok healthy, $bad unhealthy host(s)."))
                if ($bad) {
                    & $finding $(if ($ok) { 'Medium' } else { 'High' }) 'Health' $(if ($ok) { 'Unhealthy backend hosts' } else { 'Every backend host is unhealthy' }) $row "Pool $poolName (settings $settings) of $(& $text $row 'name'): $bad unhealthy, $ok healthy." $(if ($ok) { 'Capacity is reduced.' } else { 'Requests to this pool fail with 502 Bad Gateway.' }) 'Open Backend health in the portal for the reason (probe status code, certificate, NSG, DNS) and fix the backend or the probe.' "$docs/application-gateway/application-gateway-backend-health-troubleshooting" 'Medium'
                    $issues.Add("$poolName $(if ($ok) { 'partly' } else { 'fully' }) unhealthy")
                }
            }
        }
        if ($v1) {
            & $finding 'High' 'Retirement' 'Application Gateway v1 (retired)' $row "$(& $text $row 'name') is $tier v1 ($(& $text $row 'sku')); v1 was retired on 28 April 2026." 'No support, no autoscaling, zone redundancy or host metrics.' 'Migrate to Standard_v2 or WAF_v2 (the migration script clones the configuration).' "$docs/application-gateway/migrate-v1-v2" 'High'
            $issues.Add('v1 retired')
        }
        $instances = if ([int](& $get $row 'minCapacity') -gt 0) { [int](& $get $row 'minCapacity') } else { [int](& $get $row 'capacity') }
        if ($state -ne 'Stopped' -and $instances -eq 1 -and -not $v1) {
            & $finding 'Medium' 'Resilience' 'Application Gateway with one instance' $row "$(& $text $row 'name') runs $(if ([int](& $get $row 'minCapacity') -gt 0) { 'a minimum of 1 instance (autoscale)' } else { '1 instance' })." 'An instance update or failure interrupts traffic until a new one starts.' 'Set the minimum instance count (or capacity) to 2 or more.' "$docs/application-gateway/application-gateway-autoscaling-zone-redundant"
        }
        & $balancer $row 'Application Gateway' "$tier ($(& $text $row 'sku'))" $state $pools.Count $members.ToArray() $null ($issues -join ', ')
    }

    # --- Traffic Manager ---------------------------------------------------------------------------------------------
    foreach ($row in (& $rowsOf 'trafficManager')) {
        $status = & $text $row 'status'
        $members = [System.Collections.Generic.List[object]]::new()
        $probe = "$(& $text $row 'monitorProtocol') $(& $text $row 'monitorPort')$(if (& $text $row 'monitorPath') { " $(& $text $row 'monitorPath')" })"
        foreach ($e in @(& $list (& $get $row 'endpoints'))) {
            $monitor = & $text $e 'properties.endpointMonitorStatus'; $endpointStatus = & $text $e 'properties.endpointStatus'
            $health = if ($endpointStatus -eq 'Disabled' -or $monitor -in 'Disabled', 'Stopped', 'Inactive') { 'Disabled' } elseif ($monitor -eq 'Online') { 'Healthy' } elseif ($monitor -eq 'Degraded') { 'Unhealthy' } else { 'Unknown' }
            $members.Add((& $backend $row 'Traffic Manager' (& $text $row 'routing') (& $text $e 'name') (& $text $e 'properties.target') $health $null $probe "Monitor: $(if ($monitor) { $monitor } else { 'unknown' }); endpoint $endpointStatus."))
        }
        $issues = [System.Collections.Generic.List[string]]::new()
        $live = @($members | Where-Object Health -NE 'Disabled')
        $degraded = @($live | Where-Object Health -EQ 'Unhealthy')
        if ($status -eq 'Disabled') {
            & $finding 'Low' 'Configuration' 'Traffic Manager profile disabled' $row "$(& $text $row 'name') is disabled: its DNS name answers NXDOMAIN." 'Clients using it can''t resolve the service.' 'Enable it, or delete it if it is no longer used.' "$docs/traffic-manager/traffic-manager-manage-profiles"
            $issues.Add('disabled')
        }
        elseif ($degraded.Count) {
            $all = $degraded.Count -eq $live.Count
            & $finding $(if ($all) { 'High' } else { 'Medium' }) 'Health' $(if ($all) { 'Every Traffic Manager endpoint is degraded' } else { 'Traffic Manager endpoints degraded' }) $row "$(& $text $row 'name'): $(@($degraded | ForEach-Object { $_.Backend }) -join ', ') degraded (probe $probe)." $(if ($all) { 'Traffic Manager returns every endpoint anyway (all down is treated as all up): clients reach failing endpoints.' } else { 'Traffic is moved to the other endpoints.' }) 'Check the endpoints answer the monitor (protocol, port and path) with 200.' "$docs/traffic-manager/traffic-manager-troubleshooting-degraded" 'Medium'
            $issues.Add("$($degraded.Count) endpoint(s) degraded")
        }
        & $balancer $row 'Traffic Manager' (& $text $row 'routing') $status 1 $live $null ($issues -join ', ')
    }

    $rank = (Get-AACSeverityRank).Rank
    $order = @{ Unhealthy = 0; Partial = 1; Unknown = 2; 'Not measured' = 3; Disabled = 4; Healthy = 5 }
    $balancerOrder = @{ Unhealthy = 0; Degraded = 1; Unknown = 2; Stopped = 3; Healthy = 4 }
    $sortedBackends = @($backends | Sort-Object -Property @{ Expression = { $order[$_.Health] } }, Balancer, Pool, Backend)
    $sortedBalancers = @($balancers | Sort-Object -Property @{ Expression = { $balancerOrder[$_.Health] } }, Balancer)
    $sortedFindings = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Category, Resource, Finding)
    @{
        Backends  = $sortedBackends
        Balancers = $sortedBalancers
        Findings  = $sortedFindings
        Notices   = @($notices)
        Stats     = @{
            Balancers = $sortedBalancers.Count
            Unhealthy = @($sortedBalancers | Where-Object Health -EQ 'Unhealthy').Count
            Degraded  = @($sortedBalancers | Where-Object Health -EQ 'Degraded').Count
            Backends  = $sortedBackends.Count
            Down      = @($sortedBackends | Where-Object { $_.Health -in 'Unhealthy', 'Partial' }).Count
            Retired   = @($sortedFindings | Where-Object Category -EQ 'Retirement').Count
            High      = @($sortedFindings | Where-Object Severity -EQ 'High').Count
        }
    }
}
