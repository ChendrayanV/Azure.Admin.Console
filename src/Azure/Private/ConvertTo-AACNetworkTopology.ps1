function ConvertTo-AACNetworkTopology {
    <#
    .SYNOPSIS
        Turns the resource map (ConvertTo-AACResourceMap) of the networks
        into the network topology: the tenant's hierarchy around them, each
        virtual network's role (hub, spoke, peered, standalone), network
        virtual appliances, Virtual WAN hubs, peerings to networks you can't
        see, and what to look at.
    .DESCRIPTION
        No Azure calls: Show-AACNetworkTopology reads, ConvertTo-AACResourceMap
        draws the networks, this arranges them.

        The boxes, by -GroupBy:
          ManagementGroup  tenant > management group(s) > subscription >
                           region > resource group > virtual network > subnet
          Subscription     subscription > region > resource group > ...
          Region           region > virtual network > subnet
        A resource group that spans regions is drawn once in each.

        A network interface is drawn as part of its VM: the VM shows its IPs,
        takes the NIC's NSG chip and its links, and is marked as a network
        virtual appliance (nva) when the NIC forwards IP traffic. Route next
        hops already point at the VM, firewall or appliance that has the IP.

        Each virtual network gets a role:
          hub         gateway transit allowed on a peering, or a gateway,
                      firewall or appliance and a peering, or 3+ peerings
          spoke       peered with a hub (hub: which one)
          peered      peered, but with no hub
          standalone  no peerings
        A Virtual WAN hub is a hub box of its own, with its gateways and
        firewall in it, and the networks connected to it (their peerings to
        the hub's managed network, HV_<hub>_...) drawn to it. A peering to a
        network you can't see gets a box marked outside your view.

        Findings (Severity, Finding, Resource, Detail):
          High    a peering that isn't Connected; a route to an IP nothing
                  you can see has
          Medium  a spoke subnet whose internet traffic isn't sent through a
                  firewall or appliance (no 0.0.0.0/0 route to one)
          Info    a peering to a network you can't see; a standalone network

        -Map is changed in place and returned with Findings, Layout (the
        layout that suits it: 'hubspoke' when there are hubs with spokes,
        else 'layered') and Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # ConvertTo-AACResourceMap's result.
        [Parameter(Mandatory)]
        [hashtable] $Map,

        # The Resource Graph rows it was made from (inside and outside the scope).
        [AllowEmptyCollection()]
        [object[]] $Resource = @(),

        # Subscription rows: subscriptionId, name, chain (managementGroupAncestorsChain).
        [AllowEmptyCollection()]
        [object[]] $Subscription = @(),

        [ValidateSet('ManagementGroup', 'Subscription', 'Region')]
        [string] $GroupBy = 'ManagementGroup',

        [string] $TenantName = 'Tenant'
    )

    function Get-Value($Row, [string] $Key) {
        if ($Row -isnot [System.Collections.IDictionary]) { return $null }
        if ($Row.Contains($Key)) { return $Row[$Key] }
        foreach ($name in $Row.Keys) { if ($name -eq $Key) { return $Row[$name] } }
        $null
    }
    function Get-Path($Row, [string[]] $Keys) { $value = $Row; foreach ($key in $Keys) { $value = Get-Value $value $key; if ($null -eq $value) { return $null } }; $value }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    # Every key this reads, on every box and resource: strict mode allows no missing ones.
    $clusterDefaults = @{ role = ''; hub = ''; vhub = $false; hiddenRemote = $false; context = ''; peerCount = 0; egress = ''; prefixLength = 0; location = ''; subscriptionId = ''; resourceGroup = ''; type = ''; prefix = '' }
    $nodeDefaults = @{ nva = $false; context = ''; hiddenRemote = $false }
    $complete = { param($Item, [hashtable] $Defaults) foreach ($key in $Defaults.Keys) { if (-not $Item.Contains($key)) { $Item[$key] = $Defaults[$key] } } }
    $clusters = [ordered]@{}
    foreach ($c in $Map.Clusters) { & $complete $c $clusterDefaults; $clusters[$c.id] = $c }
    $nodes = [ordered]@{}
    foreach ($n in $Map.Nodes) { & $complete $n $nodeDefaults; $nodes[$n.id] = $n }
    $rows = @{}
    foreach ($row in $Resource) { $id = & $lower (Get-Value $row 'id'); if ($id -and -not $rows.Contains($id)) { $rows[$id] = $row } }
    $edges = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $Map.Edges) { if (-not $e.Contains('warn')) { $e['warn'] = $false }; $edges.Add($e) }
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Title, [string] $Resource, [string] $Detail, [string] $Id)
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.NetworkTopologyFinding'; Severity = $Severity; Finding = $Title; Resource = $Resource; Detail = $Detail; ResourceId = $Id })
    }
    $counter = @{ Next = 1 }
    $addEdge = {
        param([string] $From, [string] $To, [string] $Kind, [string] $Label)
        $edges.Add(@{ id = "t$($counter.Next)"; source = $From; target = $To; kind = $Kind; label = $Label; view = ''; warn = $false })
        $counter.Next++
    }

    # --- 1. A NIC is part of its VM ---------------------------------------------------------------
    $merged = @{}
    foreach ($nic in @($nodes.Values | Where-Object { $_.type -eq 'microsoft.network/networkinterfaces' })) {
        $properties = Get-Value $rows[$nic.id] 'properties'
        $forwarding = [string](Get-Value $properties 'enableIPForwarding') -eq 'True'
        $vmId = & $lower (Get-Path $properties 'virtualMachine', 'id')
        if (-not $vmId -or -not $nodes.Contains($vmId)) {
            if ($forwarding) { $nic.nva = $true; $nic.typeLabel = 'Network virtual appliance (NIC)' }
            continue
        }
        $vm = $nodes[$vmId]
        foreach ($ip in @($nic.facts)) { if ($ip -and @($vm.facts) -notcontains $ip) { $vm.facts = @(@($vm.facts) + $ip) } }
        if ($forwarding -and -not $vm.nva) {
            $vm.nva = $true
            $vm.typeLabel = 'Network virtual appliance'
            $vm.facts = @(@('IP forwarding') + @($vm.facts))
        }
        foreach ($chip in @($nic.chips)) {
            $vm.chips = @(@($vm.chips) + $chip)
            if ($nodes.Contains($chip.id)) { $nodes[$chip.id].appliedTo = @(@($nodes[$chip.id].appliedTo) | ForEach-Object { if ($_ -eq $nic.id) { $vmId } else { $_ } }) }
        }
        if (-not $vm.parent -or ($clusters.Contains($nic.parent) -and $clusters[$nic.parent].kind -eq 'subnet' -and -not ($clusters.Contains($vm.parent) -and $clusters[$vm.parent].kind -eq 'subnet'))) { $vm.parent = $nic.parent }
        $merged[$nic.id] = $vmId
        $nodes.Remove($nic.id)
    }
    if ($merged.Count) {
        $seen = @{}
        $kept = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $edges) {
            if ($merged.Contains($e.source)) { $e.source = $merged[$e.source] }
            if ($merged.Contains($e.target)) { $e.target = $merged[$e.target] }
            if ($e.source -eq $e.target) { continue }
            $key = "$($e.kind)|$($e.view)|$((@($e.source, $e.target) | Sort-Object) -join '|')"
            if ($seen.Contains($key)) { continue }
            $seen[$key] = $true
            $kept.Add($e)
        }
        $edges = $kept
    }

    # --- 2. Virtual WAN hubs are hub boxes; peerings you can't see get a box ---------------------
    foreach ($hub in @($nodes.Values | Where-Object { $_.type -eq 'microsoft.network/virtualhubs' })) {
        $properties = Get-Value $rows[$hub.id] 'properties'
        $clusters[$hub.id] = @{
            id = $hub.id; kind = 'vnet'; parent = $hub.parent; name = $hub.name; icon = 'vhub'; external = $hub.external; badges = @(); chips = @()
            detail = @(@([string](Get-Value $properties 'addressPrefix'), $hub.location, 'Virtual WAN hub') | Where-Object { $_ })
            type = 'microsoft.network/virtualhubs'; resourceGroup = $hub.resourceGroup; subscriptionId = $hub.subscriptionId; location = $hub.location; vhub = $true
        }
        & $complete $clusters[$hub.id] $clusterDefaults
        $nodes.Remove($hub.id)
    }
    foreach ($n in @($nodes.Values)) {
        $hubId = & $lower (Get-Path $rows[$n.id] 'properties', 'virtualHub', 'id')
        if ($hubId -and $clusters.Contains($hubId)) { $n.parent = $hubId }
    }
    $vhubByName = @{}
    foreach ($c in @($clusters.Values | Where-Object { $_.vhub })) { $vhubByName[(& $lower $c.name)] = $c.id }
    $hidden = @{}
    # Only the networks in scope: a network outside it (drawn because one in
    # scope peers with it) has peerings of its own that weren't followed.
    foreach ($vnet in @($clusters.Values | Where-Object { $_.kind -eq 'vnet' -and -not $_.vhub -and -not $_.external })) {
        foreach ($peering in @(Get-Path $rows[$vnet.id] 'properties', 'virtualNetworkPeerings')) {
            if ($null -eq $peering) { continue }
            $remote = & $lower (Get-Path $peering 'properties', 'remoteVirtualNetwork', 'id')
            if (-not $remote -or $clusters.Contains($remote)) { continue }
            $state = [string](Get-Path $peering 'properties', 'peeringState')
            $remoteName = ($remote -split '/')[-1]
            # A Virtual WAN hub's managed network: HV_<hub name>_<guid>.
            if ($remoteName -match '^hv_(.+)_[0-9a-f-]{36}$' -and $vhubByName.Contains($Matches[1])) {
                & $addEdge $vnet.id $vhubByName[$Matches[1]] 'peering' (@($state, 'Virtual WAN') -join ' · ')
                continue
            }
            if (-not $hidden.Contains($remote)) {
                $hidden[$remote] = $true
                $clusters[$remote] = @{
                    id = $remote; kind = 'vnet'; parent = ''; name = $remoteName; icon = 'vnet'; external = $true; badges = @(); chips = @()
                    detail = @('outside your view'); type = 'microsoft.network/virtualnetworks'; hiddenRemote = $true
                    subscriptionId = ($remote -split '/')[2]; resourceGroup = ($remote -split '/')[4]; location = ''
                }
                & $complete $clusters[$remote] $clusterDefaults
                & $finding 'Info' 'Peered with a network you can''t see' $vnet.name "$($vnet.name) is peered with $remoteName ($remote), which isn't visible to your account - another tenant, or no Reader access." $vnet.id
            }
            & $addEdge $vnet.id $remote 'peering' $state
        }
    }

    # --- 3. Roles: hubs, spokes, peered, standalone ------------------------------------------------
    $ancestor = {
        param([string] $Id, [string] $Kind)
        $current = if ($nodes.Contains($Id)) { $nodes[$Id].parent } elseif ($clusters.Contains($Id)) { $clusters[$Id].parent } else { '' }
        while ($current -and $clusters.Contains($current)) { if ($clusters[$current].kind -eq $Kind) { return $current }; $current = $clusters[$current].parent }
        ''
    }
    $vnetOf = { param([string] $Id) if ($clusters.Contains($Id) -and $clusters[$Id].kind -eq 'vnet') { $Id } else { & $ancestor $Id 'vnet' } }
    $peers = @{}
    $peeringEdges = @($edges | Where-Object { $_.kind -eq 'peering' })
    foreach ($e in $peeringEdges) {
        $a = & $vnetOf $e.source; $b = & $vnetOf $e.target
        if (-not $a -or -not $b -or $a -eq $b) { continue }
        foreach ($pair in @(@($a, $b), @($b, $a))) {
            if (-not $peers.Contains($pair[0])) { $peers[$pair[0]] = [System.Collections.Generic.List[string]]::new() }
            if (-not $peers[$pair[0]].Contains($pair[1])) { $peers[$pair[0]].Add($pair[1]) }
        }
        if ($e.label -notmatch '(?i)^connected') {
            $ends = @($clusters[$a].name, $clusters[$b].name) | Sort-Object
            & $finding 'High' 'Peering not connected' ($ends -join ' <-> ') "The peering between $($clusters[$a].name) and $($clusters[$b].name) is $(@(($e.label -split ' · '))[0]). Traffic doesn't flow until both sides are Connected: re-sync or recreate the side that is Initiated or Disconnected." $a
            $e.warn = $true
        }
    }
    $transitTypes = @('microsoft.network/virtualnetworkgateways', 'microsoft.network/azurefirewalls')
    $devices = @{}
    foreach ($n in $nodes.Values) {
        if ($n.type -in $transitTypes -or $n.nva) { $v = & $vnetOf $n.id; if ($v) { $devices[$v] = $true } }
    }
    $vnets = @($clusters.Values | Where-Object { $_.kind -eq 'vnet' })
    foreach ($vnet in $vnets) {
        $transit = @(Get-Path $rows[$vnet.id] 'properties', 'virtualNetworkPeerings' | Where-Object { $_ -and [string](Get-Path $_ 'properties', 'allowGatewayTransit') -eq 'True' }).Count -gt 0
        $count = if ($peers.Contains($vnet.id)) { $peers[$vnet.id].Count } else { 0 }
        $vnet.peerCount = $count
        $vnet.role = if ($vnet.hiddenRemote) { 'outside' }
        elseif ($vnet.vhub -or $transit -or ($devices.Contains($vnet.id) -and $count -ge 1) -or $count -ge 3) { 'hub' }
        elseif ($count) { 'peered' }
        else { 'standalone' }
    }
    foreach ($vnet in $vnets) {
        if ($vnet.role -ne 'peered') { continue }
        $hub = @($peers[$vnet.id] | Where-Object { $clusters[$_].role -eq 'hub' }) | Select-Object -First 1
        if ($hub) { $vnet.role = 'spoke'; $vnet.hub = $hub }
    }
    # A hidden network that several of yours peer with is most likely their hub.
    foreach ($vnet in @($vnets | Where-Object { $_.role -eq 'outside' })) {
        if ($peers.Contains($vnet.id) -and $peers[$vnet.id].Count -ge 2) {
            $vnet.role = 'hub'
            foreach ($other in $peers[$vnet.id]) { if ($clusters[$other].role -eq 'peered') { $clusters[$other].role = 'spoke'; $clusters[$other].hub = $vnet.id } }
        }
    }
    foreach ($vnet in $vnets) {
        $label = switch ($vnet.role) { 'hub' { 'HUB' } 'spoke' { "spoke of $($clusters[$vnet.hub].name)" } 'peered' { 'peered' } 'standalone' { 'standalone' } default { '' } }
        if ($label) { $vnet.detail = @(@($label) + @($vnet.detail)) }
        if ($vnet.role -eq 'standalone') { & $finding 'Info' 'Standalone network' $vnet.name "$($vnet.name) isn't peered with any network: it reaches others only through public endpoints, a gateway of its own, or not at all." $vnet.id }
    }

    # --- 4. Egress: does a spoke's internet traffic go through a firewall or appliance? -----------
    $inspectors = @{}
    foreach ($n in $nodes.Values) { if ($n.type -eq 'microsoft.network/azurefirewalls' -or $n.nva) { $inspectors[$n.id] = $true } }
    foreach ($table in @($nodes.Values | Where-Object { $_.type -eq 'microsoft.network/routetables' })) {
        foreach ($route in @($table.routes)) {
            if ($route.risk -eq 'high') { & $finding 'High' 'Route to an unknown next hop' $table.name "$($route.name): $($route.prefix) -> $($route.nextHop) - $($route.reason)" $table.id }
        }
    }
    foreach ($subnet in @($clusters.Values | Where-Object { $_.kind -eq 'subnet' })) {
        $vnet = $clusters[$subnet.parent]
        if (-not $vnet -or $vnet.role -ne 'spoke') { continue }
        if ($subnet.name -in 'GatewaySubnet', 'AzureFirewallSubnet', 'AzureFirewallManagementSubnet', 'AzureBastionSubnet', 'RouteServerSubnet') { continue }
        # Only subnets with workloads that reach out: VMs and scale sets, not private endpoints.
        if (-not @($nodes.Values | Where-Object { $_.parent -eq $subnet.id -and $_.type -in 'microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets' -and -not $_.nva }).Count) { continue }
        $tables = @($nodes.Values | Where-Object { $_.type -eq 'microsoft.network/routetables' -and @($_.appliedTo) -contains $subnet.id })
        $inspected = @($tables | ForEach-Object { $_.routes } | Where-Object { $_.prefix -eq '0.0.0.0/0' -and ($inspectors.Contains($_.target) -or $_.nextHopType -eq 'VirtualNetworkGateway') }).Count -gt 0
        if (-not $inspected) {
            $subnet.egress = 'direct'
            & $finding 'Medium' 'Egress not inspected' "$($vnet.name)/$($subnet.name)" "No 0.0.0.0/0 route from $($subnet.name) goes to a firewall or appliance$(if (-not $tables.Count) { ' (it has no route table)' }): its internet traffic leaves without inspection. Add a route table with 0.0.0.0/0 to the hub's firewall." $subnet.id
        }
        else { $subnet.egress = 'inspected' }
    }

    # --- 5. The boxes around the networks ----------------------------------------------------------
    $chains = @{}
    foreach ($row in $Subscription) { $chains[(& $lower (Get-Value $row 'subscriptionId'))] = @(Get-Value $row 'chain') }
    $regionOf = {
        param($Item)
        $location = if ($Item.location) { $Item.location } elseif ($rows.Contains($Item.id)) { Get-Value $rows[$Item.id] 'location' } else { '' }
        if ($location) { & $lower $location } else { 'global' }
    }
    $ensure = {
        param([string] $Id, [string] $Kind, [string] $Parent, [string] $Name, [string[]] $Detail, [string] $Icon)
        if (-not $clusters.Contains($Id)) {
            $clusters[$Id] = @{ id = $Id; kind = $Kind; parent = $Parent; name = $Name; detail = @($Detail | Where-Object { $_ }); icon = $Icon; external = $false; badges = @(); chips = @() }
            & $complete $clusters[$Id] $clusterDefaults
        }
        $Id
    }
    $tenantId = 'tenant'
    $mgParent = {
        param([string] $SubscriptionKey)
        $chain = @($chains[$SubscriptionKey] | Where-Object { $_ })
        if (-not $chain.Count) { return (& $ensure $tenantId 'tenant' '' $TenantName @() 'resource') }
        $parent = & $ensure $tenantId 'tenant' '' $TenantName @() 'resource'
        # The chain runs from the subscription's own management group to the root.
        for ($i = $chain.Count - 1; $i -ge 0; $i--) {
            $name = [string](Get-Value $chain[$i] 'name')
            $display = [string](Get-Value $chain[$i] 'displayName')
            if ($i -eq $chain.Count - 1) { $clusters[$tenantId].name = $(if ($display) { $display } else { $TenantName }); continue }
            $parent = & $ensure "/providers/microsoft.management/managementgroups/$(& $lower $name)" 'managementgroup' $parent $(if ($display) { $display } else { $name }) @($name) 'resource'
        }
        $parent
    }
    # Who sits in a resource group: re-homed by region below.
    $context = @{}
    $children = @(@($clusters.Values | Where-Object { $_.kind -eq 'vnet' }) + @($nodes.Values))
    $outside = ''
    foreach ($item in $children) {
        $group = $item.parent
        if ($item.hiddenRemote) {
            $outside = & $ensure 'outside' 'resourcegroup' '' 'Outside your view' @('networks peered with yours that your account can''t see') 'resourcegroup'
            $clusters['outside'].external = $true
            $item.parent = $outside
            continue
        }
        if (-not $group -or -not $clusters.Contains($group) -or $clusters[$group].kind -ne 'resourcegroup') { continue }
        $rg = $clusters[$group]
        $subscriptionKey = & $lower (($group -split '/')[2])
        $subscriptionBox = "/subscriptions/$subscriptionKey"
        $region = & $regionOf $item
        $subscriptionName = if ($clusters.Contains($subscriptionBox)) { $clusters[$subscriptionBox].name } else { $subscriptionKey }
        $item.context = "$subscriptionName › $region › $($rg.name)"
        switch ($GroupBy) {
            'Region' {
                $item.parent = & $ensure "region|$region" 'region' '' $region @() 'resource'
            }
            default {
                $regionBox = & $ensure "$subscriptionBox|$region" 'region' $subscriptionBox $region @() 'resource'
                $box = & $ensure "$group|$region" 'resourcegroup' $regionBox $rg.name @($rg.detail) 'resourcegroup'
                $clusters[$box].external = $rg.external
                $item.parent = $box
            }
        }
        $context[$group] = $true
    }
    foreach ($group in @($context.Keys)) { $clusters.Remove($group) }
    if ($GroupBy -eq 'Region') {
        foreach ($id in @($clusters.Keys)) { if ($clusters[$id].kind -in 'subscription', 'resourcegroup' -and $id -ne 'outside') { $clusters.Remove($id) } }
    }
    elseif ($GroupBy -eq 'ManagementGroup') {
        foreach ($c in @($clusters.Values | Where-Object { $_.kind -eq 'subscription' })) { $c.parent = & $mgParent (& $lower (($c.id -split '/')[2])) }
    }
    # Boxes left with nothing in them.
    do {
        $used = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($c in $clusters.Values) { if ($c.parent) { [void]$used.Add($c.parent) } }
        foreach ($n in $nodes.Values) { if ($n.parent) { [void]$used.Add($n.parent) } }
        $empty = @($clusters.Values | Where-Object { $_.kind -in 'tenant', 'managementgroup', 'subscription', 'region', 'resourcegroup' -and -not $used.Contains($_.id) } | ForEach-Object { $_.id })
        foreach ($id in $empty) { $clusters.Remove($id) }
    } while ($empty.Count)

    # A subnet's size on the map follows its prefix: a /16 is wider than a /28.
    foreach ($subnet in @($clusters.Values | Where-Object { $_.kind -eq 'subnet' })) {
        if ([string]$subnet.prefix -match '/(\d+)') { $subnet.prefixLength = [int]$Matches[1] }
    }

    # Outermost first, as the page draws them.
    $depth = { param($C) $d = 0; $p = $C.parent; while ($p -and $clusters.Contains($p)) { $d++; $p = $clusters[$p].parent }; $d }
    $Map.Clusters = @($clusters.Values | Sort-Object -Property { & $depth $_ }, { $_.name } -Stable)
    $Map.Nodes = @($nodes.Values)
    $Map.Edges = @($edges)
    $hubs = @($vnets | Where-Object { $_.role -eq 'hub' })
    $spokes = @($vnets | Where-Object { $_.role -eq 'spoke' })
    $count = { param([string[]] $Types) @($nodes.Values | Where-Object { $_.type -in $Types -and -not $_.external }).Count }
    $rank = @{ High = 0; Medium = 1; Info = 2 }
    $Map.Findings = @($findings | Sort-Object -Property { $rank[$_.Severity] }, Finding, Resource)
    $Map.Layout = if ($hubs.Count -and $spokes.Count) { 'hubspoke' } else { 'layered' }
    $Map.Stats = @{
        ManagementGroups = @($clusters.Values | Where-Object { $_.kind -eq 'managementgroup' }).Count
        Subscriptions    = @(@($vnets | Where-Object { -not $_.hiddenRemote }) | ForEach-Object { & $lower $_.subscriptionId } | Select-Object -Unique).Count
        Regions          = @(@($vnets | Where-Object { -not $_.hiddenRemote }) | ForEach-Object { & $regionOf $_ } | Select-Object -Unique).Count
        Networks         = @($vnets | Where-Object { -not $_.hiddenRemote -and -not $_.vhub }).Count
        VirtualHubs      = @($vnets | Where-Object { $_.vhub }).Count
        Subnets          = @($clusters.Values | Where-Object { $_.kind -eq 'subnet' }).Count
        Hubs             = $hubs.Count
        Spokes           = $spokes.Count
        Standalone       = @($vnets | Where-Object { $_.role -eq 'standalone' }).Count
        Hidden           = $hidden.Count
        Peerings         = $peeringEdges.Count
        Gateways         = & $count @('microsoft.network/virtualnetworkgateways', 'microsoft.network/vpngateways', 'microsoft.network/expressroutegateways', 'microsoft.network/p2svpngateways')
        Firewalls        = & $count @('microsoft.network/azurefirewalls')
        Appliances       = @($nodes.Values | Where-Object { $_.nva }).Count
        PrivateEndpoints = & $count @('microsoft.network/privateendpoints')
        VirtualMachines  = & $count @('microsoft.compute/virtualmachines')
        ScaleSets        = & $count @('microsoft.compute/virtualmachinescalesets')
        Bastions         = & $count @('microsoft.network/bastionhosts')
        Resources        = @($nodes.Values | Where-Object { -not $_.external }).Count
        Outside          = @($nodes.Values | Where-Object { $_.external }).Count
        Connections      = $edges.Count
        Findings         = $findings.Count
    }
    $Map
}
