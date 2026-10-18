function Read-AACNetworkTopology {
    <#
    .SYNOPSIS
        Reads the networks in a scope - and the peered networks, the PaaS
        behind private endpoints and the route next hops beyond it - and builds
        the network topology's model. Shared by Show-AACNetworkTopology and
        Export-AACDiagram.
    .DESCRIPTION
        Runs inside Invoke-AACProgress (it reports its steps there). Reads
        Resource Graph: the subscriptions with their management group chain,
        the network fabric (and, unless -NetworkOnly, NICs, VMs, scale sets and
        private endpoints); then what is beyond the scope that those refer to.
        Returns @{ Map (ConvertTo-AACNetworkTopology's result); Title; Facts }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $ManagementGroupId = @(),

        [string[]] $SubscriptionId = @(),

        # Regions, lower case and without spaces.
        [string[]] $Location = @(),

        [ValidateSet('ManagementGroup', 'Subscription', 'Region')]
        [string] $GroupBy = 'ManagementGroup',

        [switch] $NetworkOnly,

        [string[]] $ExcludeType = @(),

        [string] $Title
    )

    $request = @{
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        Location          = @($Location | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() -replace '\s', '' })
        NetworkOnly       = [bool]$NetworkOnly
    }
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    # A value deep in a row, or nothing when a step along the way is missing.
    $at = {
        param($Row, [string[]] $Keys)
        $value = $Row
        foreach ($key in $Keys) { if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($key)) { return $null }; $value = $value[$key] }
        $value
    }
    $columns = '| project id, name, type, kind, location, resourceGroup, subscriptionId, sku, properties, tags'
    $fabric = @(
        'microsoft.network/virtualnetworks', 'microsoft.network/virtualnetworkgateways', 'microsoft.network/connections',
        'microsoft.network/localnetworkgateways', 'microsoft.network/expressroutecircuits', 'microsoft.network/virtualwans',
        'microsoft.network/virtualhubs', 'microsoft.network/vpngateways', 'microsoft.network/expressroutegateways',
        'microsoft.network/p2svpngateways', 'microsoft.network/azurefirewalls', 'microsoft.network/networksecuritygroups',
        'microsoft.network/routetables', 'microsoft.network/bastionhosts', 'microsoft.network/natgateways',
        'microsoft.network/loadbalancers', 'microsoft.network/applicationgateways', 'microsoft.network/privatelinkservices',
        'microsoft.network/dnsresolvers'
    )
    $workloads = @('microsoft.network/networkinterfaces', 'microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets', 'microsoft.network/privateendpoints')
    $asset = Get-AACResourceMapAsset
    $graph = {
        param([System.Collections.IDictionary] $Query, [switch] $Everywhere)
        if ($Everywhere) { (Invoke-AACGraphBatch -Query $Query).Rows }
        else { (Invoke-AACGraphBatch -Query $Query -SubscriptionId $request.SubscriptionId -ManagementGroupId $request.ManagementGroupId).Rows }
    }
    $byId = {
        # Rows by resource ID, 200 a query, the queries at once.
        param([string[]] $Ids)
        $chunks = [ordered]@{}
        for ($i = 0; $i -lt $Ids.Count; $i += 200) {
            $chunk = $Ids[$i..([Math]::Min($i + 199, $Ids.Count - 1))]
            $chunks["ids$i"] = "resources | where id in~ ($((@($chunk | ForEach-Object { & $quote $_ })) -join ', ')) $columns"
        }
        if (-not $chunks.Count) { return @() }
        $read = & $graph $chunks -Everywhere
        foreach ($name in @($chunks.Keys)) { @($read[$name]) }
    }

    # --- The networks and everything in and around them -----------------------------------------
    Update-AACProgress -Id 'read' -Indeterminate -Description 'Reading the networks from Azure Resource Graph'
    $types = @($fabric) + @(if (-not $request.NetworkOnly) { $workloads })
    $where = if ($request.Location.Count) { " | where location in~ ($((@($request.Location | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $queries = [ordered]@{
        subscriptions = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name, chain = properties.managementGroupAncestorsChain" }
        resources     = "resources | where type in~ ($((@($types | ForEach-Object { & $quote $_ })) -join ', '))$where $columns"
    }
    # Appliances need their NICs and VMs even with -NetworkOnly: the NICs that forward IP traffic.
    if ($request.NetworkOnly) { $queries['appliances'] = "resources | where type =~ 'microsoft.network/networkinterfaces' and properties.enableIPForwarding == true$where $columns" }
    $read = & $graph $queries
    $resources = [System.Collections.Generic.List[object]]::new()
    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($read['resources']) + @($read['appliances'])) { if ($row -and $known.Add([string]$row['id'])) { $resources.Add($row) } }
    if ($request.NetworkOnly) {
        $vms = @(foreach ($row in @($read['appliances'])) { [string](& $at $row 'properties', 'virtualMachine', 'id') }) | Where-Object { $_ }
        foreach ($row in @(& $byId @($vms))) { if ($known.Add([string]$row['id'])) { $resources.Add($row) } }
    }
    $subscriptions = @($read['subscriptions'])
    Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} network resource(s) in {1:N0} subscription(s)' -f $resources.Count, @($resources | ForEach-Object { $_['subscriptionId'] } | Sort-Object -Unique).Count)

    # --- Beyond the scope: peered networks, the PaaS behind private endpoints, route next hops ----
    Update-AACProgress -Id 'beyond' -Indeterminate -Description 'Following peerings, private endpoints and routes beyond the scope'
    $wanted = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $resources) {
        $type = ([string]$row['type']).ToLowerInvariant()
        if ($type -eq 'microsoft.network/virtualnetworks') {
            foreach ($peering in @(& $at $row 'properties', 'virtualNetworkPeerings')) { $remote = [string](& $at $peering 'properties', 'remoteVirtualNetwork', 'id'); if ($remote -and -not $known.Contains($remote)) { [void]$wanted.Add($remote) } }
        }
        if ($type -eq 'microsoft.network/privateendpoints') {
            foreach ($connection in @(& $at $row 'properties', 'privateLinkServiceConnections') + @(& $at $row 'properties', 'manualPrivateLinkServiceConnections')) {
                $target = [string](& $at $connection 'properties', 'privateLinkServiceId')
                if ($target -and -not $known.Contains($target)) { [void]$wanted.Add($target) }
            }
        }
    }
    $external = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @(& $byId @($wanted))) { if ($row -and $known.Add([string]$row['id'])) { $external.Add($row) } }
    # Route next hops that nothing read so far has.
    $owned = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in @($resources) + @($external)) {
        foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '"privateIPAddress":"([^"]+)"')) { [void]$owned.Add($match.Groups[1].Value) }
    }
    $hops = @(foreach ($row in $resources) {
            if (([string]$row['type']).ToLowerInvariant() -ne 'microsoft.network/routetables') { continue }
            foreach ($route in @(& $at $row 'properties', 'routes')) { [string](& $at $route 'properties', 'nextHopIpAddress') }
        }) | Where-Object { $_ -and -not $owned.Contains($_) } | Select-Object -Unique
    if ($hops) {
        $filter = (@($hops | ForEach-Object { "properties contains $(& $quote $_)" })) -join ' or '
        $owners = @((& $graph @{ hops = "resources | where type in~ ('microsoft.network/azurefirewalls', 'microsoft.network/networkinterfaces', 'microsoft.network/loadbalancers') | where $filter $columns" } -Everywhere)['hops'])
        foreach ($row in $owners) { if ($row -and $known.Add([string]$row['id'])) { $external.Add($row) } }
        # The network the next hop is in, so it's drawn in its subnet.
        $vnets = @(foreach ($row in $owners) { foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '(?i)"id":"(/subscriptions/[^"]+/virtualNetworks/[^/"]+)/subnets/')) { $match.Groups[1].Value } }) | Select-Object -Unique
        foreach ($row in @(& $byId @($vnets | Where-Object { -not $known.Contains($_) }))) { if ($row -and $known.Add([string]$row['id'])) { $external.Add($row) } }
    }
    Update-AACProgress -Id 'beyond' -Complete -Description ('Followed {0:N0} peering(s), private endpoint(s) and route(s) to {1:N0} resource(s) outside the scope' -f $wanted.Count, $external.Count)

    # --- The topology ----------------------------------------------------------------------------
    Update-AACProgress -Id 'map' -Indeterminate -Description 'Working out the hierarchy, roles and connections'
    $subscriptionNames = @{}
    foreach ($row in $subscriptions) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }
    $labels = @{}
    foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = [string]$asset.Icons.icons[$key].label }
    $map = ConvertTo-AACResourceMap -Resource $resources.ToArray() -External $external.ToArray() -SubscriptionName $subscriptionNames -IconType $asset.Icons.types -IconLabel $labels -ExcludeType @($ExcludeType | Where-Object { $_ })
    $map = ConvertTo-AACNetworkTopology -Map $map -Resource (@($resources) + @($external)) -Subscription $subscriptions -GroupBy $GroupBy
    $stats = $map.Stats
    Update-AACProgress -Id 'map' -Complete -Description ('{0:N0} network(s): {1:N0} hub(s), {2:N0} spoke(s); {3:N0} peering(s), {4:N0} connection(s)' -f $stats.Networks, $stats.Hubs, $stats.Spokes, $stats.Peerings, $stats.Connections)

    $scopeText = if ($request.ManagementGroupId.Count) { "management group $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { @($request.SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ' } else { 'every subscription you can see' }
    if ($request.Location.Count) { $scopeText += " ($($request.Location -join ', '))" }
    $facts = @(
        '{0:N0} virtual network(s)' -f $stats.Networks
        if ($stats.VirtualHubs) { '{0:N0} Virtual WAN hub(s)' -f $stats.VirtualHubs }
        '{0:N0} hub(s)' -f $stats.Hubs
        '{0:N0} spoke(s)' -f $stats.Spokes
        '{0:N0} peering(s)' -f $stats.Peerings
        '{0:N0} subscription(s)' -f $stats.Subscriptions
        '{0:N0} region(s)' -f $stats.Regions
        if ($stats.Firewalls -or $stats.Appliances) { '{0:N0} firewall(s) and appliance(s)' -f ($stats.Firewalls + $stats.Appliances) }
        if ($stats.PrivateEndpoints) { '{0:N0} private endpoint(s)' -f $stats.PrivateEndpoints }
        "drawn $((Get-Date).ToString('d MMM yyyy HH:mm'))"
    )
    @{ Map = $map; Title = $(if ($Title) { $Title } else { "Network topology: $scopeText" }); Facts = $facts }
}
