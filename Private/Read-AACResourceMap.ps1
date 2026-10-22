function Read-AACResourceMap {
    <#
    .SYNOPSIS
        Reads the resources in some resource groups (or subscriptions), those
        outside the selection they use and the route next hops, and builds the
        resource map's model. Shared by Show-AACResourceMap and
        Export-AACDiagram.
    .DESCRIPTION
        Runs inside Invoke-AACProgress (it reports its steps there). Reads
        Resource Graph: the subscriptions and resource groups, the resources;
        then, 200 IDs a query, the resources outside the selection that a
        chosen one refers to; then the owners of route next hops (a firewall
        or appliance IP) nothing read so far has, in every subscription, so a
        spoke's routes reach the hub's firewall.
        Returns @{ Map (ConvertTo-AACResourceMap's result); Title; Facts
        (the lines under the title) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $SubscriptionId = @(),

        [string[]] $ResourceGroupName = @(),

        [string[]] $ExcludeType = @(),

        [string] $Title
    )

    $SubscriptionId = @($SubscriptionId | Where-Object { $_ })
    $ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    # Resource Graph queries, several at once (Invoke-AACGraphBatch): rows
    # as hashtables (tags whose keys differ only by case are fine).
    $graph = {
        param([System.Collections.IDictionary] $Query, [string[]] $Subscriptions)
        (Invoke-AACGraphBatch -Query $Query -SubscriptionId $Subscriptions).Rows
    }
    $columns = '| project id, name, type, kind, location, resourceGroup, subscriptionId, sku, properties, tags'
    $asset = Get-AACResourceMapAsset

    # --- What to map ------------------------------------------------------------------------
    Update-AACProgress -Id 'scope' -Description 'Finding the subscriptions and resource groups' -Indeterminate
    # The subscriptions, resource groups and resources together.
    $groupFilter = if ($ResourceGroupName.Count) { " and resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $read = & $graph ([ordered]@{
            subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
            groups        = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'$($groupFilter -replace 'resourceGroup', 'name') | project name, subscriptionId"
            resources     = "resources | where isnotempty(resourceGroup)$groupFilter $columns"
        }) $SubscriptionId
    $subscriptionNames = @{}
    foreach ($row in @($read['subscriptions'])) {
        $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name']
    }
    $groups = @($read['groups'])
    if ($ResourceGroupName.Count) {
        $missing = @($ResourceGroupName | Where-Object { $name = $_; -not @($groups | Where-Object { [string]$_['name'] -eq $name }).Count })
        if ($missing.Count -eq $ResourceGroupName.Count) {
            throw "No resource group named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found$(if ($SubscriptionId.Count) { " in subscription $($SubscriptionId -join ', ')" } else { ' in any subscription you can see' })."
        }
        foreach ($name in $missing) { Write-Warning "No resource group named '$name' was found; the map leaves it out." }
    }
    Update-AACProgress -Id 'scope' -Complete -Description ('Found {0} resource group(s) in {1} subscription(s)' -f $groups.Count, @($groups | ForEach-Object { $_['subscriptionId'] } | Sort-Object -Unique).Count)

    # --- The resources, and those outside the selection they use ----------------------------
    Update-AACProgress -Id 'read' -Description 'Reading the resources from Azure Resource Graph' -Indeterminate
    $resources = @($read['resources'])
    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $resources) { [void]$known.Add([string]$row['id']) }
    $referenced = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $resources) {
        $text = ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress
        foreach ($match in [regex]::Matches($text, '(?i)/subscriptions/[^/"]+/resourcegroups/[^/"]+/providers/[^/"]+/[^/"]+/[^/"]+')) {
            if (-not $known.Contains($match.Value)) { [void]$referenced.Add($match.Value) }
        }
    }
    # Those outside it, 200 IDs a query, the queries at once.
    $external = [System.Collections.Generic.List[object]]::new()
    $ids = @($referenced)
    $chunks = [ordered]@{}
    for ($i = 0; $i -lt $ids.Count; $i += 200) {
        $chunk = $ids[$i..([Math]::Min($i + 199, $ids.Count - 1))]
        $chunks["chunk$i"] = "resources | where id in~ ($((@($chunk | ForEach-Object { & $quote $_ })) -join ', ')) $columns"
    }
    if ($chunks.Count) {
        $read = & $graph $chunks @()
        foreach ($name in @($chunks.Keys)) { foreach ($row in @($read[$name])) { $external.Add($row) } }
    }
    # Route next hops (a firewall or appliance IP) that nothing read so far
    # has: look for their owner in every subscription, so a spoke's routes
    # reach the hub's firewall.
    $owned = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($row in @($resources) + @($external)) {
        foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '"privateIPAddress":"([^"]+)"')) { [void]$owned.Add($match.Groups[1].Value) }
    }
    $hops = @(foreach ($row in $resources) {
            if ([string]$row['type'] -ne 'microsoft.network/routetables' -and [string]$row['type'] -ne 'Microsoft.Network/routeTables') { continue }
            foreach ($match in [regex]::Matches((ConvertTo-Json -InputObject $row['properties'] -Depth 30 -Compress), '"nextHopIpAddress":"([^"]+)"')) { $match.Groups[1].Value }
        }) | Where-Object { $_ -and -not $owned.Contains($_) } | Select-Object -Unique
    if ($hops) {
        $types = "'microsoft.network/azurefirewalls', 'microsoft.network/networkinterfaces', 'microsoft.network/loadbalancers', 'microsoft.network/applicationgateways'"
        $filter = (@($hops | ForEach-Object { "properties contains $(& $quote $_)" })) -join ' or '
        foreach ($row in @((& $graph @{ hops = "resources | where type in~ ($types) | where $filter $columns" } @())['hops'])) {
            if (-not $known.Contains([string]$row['id']) -and -not @($external | Where-Object { [string]$_['id'] -eq [string]$row['id'] }).Count) { $external.Add($row) }
        }
    }
    Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} resource(s), and {1:N0} outside the selection they use' -f $resources.Count, $external.Count)

    # --- The map ------------------------------------------------------------------------------
    Update-AACProgress -Id 'map' -Description 'Working out the connections and network paths' -Indeterminate
    $labels = @{}
    foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = [string]$asset.Icons.icons[$key].label }
    $map = ConvertTo-AACResourceMap -Resource $resources -External $external.ToArray() -SubscriptionName $subscriptionNames -IconType $asset.Icons.types -IconLabel $labels -ExcludeType @($ExcludeType | Where-Object { $_ })
    Update-AACProgress -Id 'map' -Complete -Description ('Mapped {0:N0} resource(s) and {1:N0} connection(s)' -f $map.Stats.Resources, $map.Stats.Connections)

    $scopeText = if ($ResourceGroupName.Count) { $ResourceGroupName -join ', ' } else { @($SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ' }
    $facts = @(
        '{0:N0} resources' -f $map.Stats.Resources
        '{0:N0} resource group(s)' -f $map.Stats.Groups
        '{0:N0} virtual network(s)' -f $map.Stats.Networks
        '{0:N0} connections' -f $map.Stats.Connections
        if ($map.Stats.Outside) { '{0:N0} outside the selection' -f $map.Stats.Outside }
        if ($map.Stats.Orphans) { '{0:N0} unattached' -f $map.Stats.Orphans }
        if ($map.Stats.Flagged) { '{0:N0} NSG / route table(s) flagged' -f $map.Stats.Flagged }
        "drawn $((Get-Date).ToString('d MMM yyyy HH:mm'))"
    )
    @{ Map = $map; Title = $(if ($Title) { $Title } else { "Resource map: $scopeText" }); Facts = $facts }
}
