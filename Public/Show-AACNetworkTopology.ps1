function Show-AACNetworkTopology {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Draws the network topology of the tenant - or of management groups,
        subscriptions or regions - as an interactive diagram: hubs with their
        spokes around them, or every network inside its tenant, management
        group, subscription, region and resource group; with the peerings,
        private endpoints and the firewalls and appliances traffic is routed
        through. Opens it in your browser, ready to save as PNG, JPEG or SVG.
    .DESCRIPTION
        Reads with Azure Resource Graph - read-only, Reader is enough, no Az
        modules - across every subscription in scope, every region:
          the management groups and subscriptions above the networks
          virtual networks and subnets, and their peerings - also across
            subscriptions, and to networks you can't see
          VPN and ExpressRoute gateways, connections, circuits, local
            gateways; Virtual WAN and its hubs and gateways
          Azure Firewalls, network virtual appliances (VMs whose NIC forwards
            IP traffic), NSGs, route tables, NAT gateways, Bastion, load
            balancers, Application Gateways, private link services, DNS
            resolvers
          virtual machines, scale sets and private endpoints in their
            subnets, and the PaaS resources the private endpoints serve
            (-NetworkOnly leaves these out)
        A peering outside the scope is followed to the network at its other
        end, and a route's next hop to the firewall or appliance that has the
        IP, so a spoke's map reaches its hub.

        The boxes (-GroupBy):
          ManagementGroup  tenant > management group > subscription > region
                           > resource group > virtual network > subnet
          Subscription     subscription > region > resource group > ...
          Region           region > virtual network > subnet
        Subnets are drawn in rows inside their network, as wide as their
        prefix is big. VMs, scale sets, Bastion, gateways, firewalls and
        private endpoints sit in the subnet they have an IP in; a VM shows
        its NIC's IPs and NSG, and an appliance is outlined in the route
        colour.

        The lines:
          VNet peering   between networks, both ways, with its state and what
                         it lets through (forwarded traffic, gateway transit,
                         remote gateway); red and dashed when not Connected
          Private link   from a private endpoint to the PaaS resource it serves
          Route          from a subnet to the firewall or appliance its routes
                         send traffic to ("0.0.0.0/0 via rt-spoke")
          Network        a gateway's connections and circuits, and the rest
        Within a network, subnets reach each other through Azure's system
        routes: no lines are drawn between them.

        Each network gets a role: hub (gateway transit, or a gateway,
        firewall or appliance and peerings, or 3+ peerings), spoke (peered
        with a hub), peered or standalone. The layout (-Layout):
          HubSpoke   each hub at the centre, its spokes in rings around it,
                     hubs side by side, the rest below; each network's box
                     says its subscription, region and resource group
          Hierarchy  the nested boxes, laid out in layers
          Auto       HubSpoke when there are hubs with spokes (the default)
        The page switches between them, and between left to right and top to
        bottom; pan, zoom, search, click for details and connections, and
        save as PNG, JPEG or SVG.

        At the prompt: tiles, the hubs and their spokes, and findings - a
        peering that isn't connected, a route to an IP nothing has, a spoke
        subnet whose internet traffic isn't sent through a firewall or
        appliance, a peering to a network you can't see, standalone networks.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups (at any depth).
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER Location
        Only these regions (e.g. 'uksouth', 'westeurope').
    .PARAMETER GroupBy
        The boxes around the networks: ManagementGroup (the default),
        Subscription or Region.
    .PARAMETER Layout
        Auto (the default), HubSpoke or Hierarchy. The page can switch too.
    .PARAMETER NetworkOnly
        Leave out virtual machines, scale sets, private endpoints and the
        PaaS resources behind them: only the network fabric - networks,
        subnets, peerings, gateways, firewalls, appliances, Bastion. For a
        large estate.
    .PARAMETER ExcludeType
        Resource types to leave out; wildcards work.
    .PARAMETER Direction
        LeftToRight (the default) or TopToBottom, inside each box. The page
        can switch it too.
    .PARAMETER Theme
        Dark (the default), Light or Blueprint.
    .PARAMETER NsgView
        Chips (the default): NSGs and route tables as chips on the subnets
        and VMs they're applied to. Cards: as resources, with lines.
    .PARAMETER HtmlPath
        Where to write the diagram. By default a file in your temp folder.
    .PARAMETER Title
        The diagram's title.
    .PARAMETER NoBrowser
        Write the diagram without opening it.
    .PARAMETER PassThru
        Also return the topology: networks with their roles, findings,
        resources, connections and the file's path.
    .EXAMPLE
        Connect-AAC
        Show-AACNetworkTopology
        Every network you can see, hubs at the centre of their spokes.
    .EXAMPLE
        Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -GroupBy Subscription -Layout Hierarchy
        A management group's networks inside their subscriptions, regions and resource groups.
    .EXAMPLE
        Show-AACNetworkTopology -NetworkOnly -Location 'uksouth', 'ukwest' -Theme Light -HtmlPath .\out\Network.html -NoBrowser
        The network fabric of two regions, written to a file.
    .EXAMPLE
        (Show-AACNetworkTopology -NoBrowser -PassThru).Findings | Where-Object Severity -EQ 'High'
        Peerings that aren't connected and routes to IPs nothing has.
    .OUTPUTS
        AAC.NetworkTopology, with -PassThru
    #>
    [CmdletBinding()]
    [OutputType('AAC.NetworkTopology')]
    param(
        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $Location,

        [ValidateSet('ManagementGroup', 'Subscription', 'Region')]
        [string] $GroupBy = 'ManagementGroup',

        [ValidateSet('Auto', 'HubSpoke', 'Hierarchy')]
        [string] $Layout = 'Auto',

        [switch] $NetworkOnly,

        [SupportsWildcards()]
        [string[]] $ExcludeType,

        [ValidateSet('LeftToRight', 'TopToBottom')]
        [string] $Direction = 'LeftToRight',

        [ValidateSet('Dark', 'Light', 'Blueprint')]
        [string] $Theme = 'Dark',

        [ValidateSet('Chips', 'Cards')]
        [string] $NsgView = 'Chips',

        [string] $HtmlPath,

        [string] $Title,

        [switch] $NoBrowser,

        [switch] $PassThru
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $htmlFullPath = if ($HtmlPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath) }
    else { Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-NetworkTopology-{0:yyyyMMdd-HHmmss}.html' -f (Get-Date)) }
    # Everything the work below needs, read here: it runs inside
    # Invoke-AACProgress, whose variables could hide ours.
    $request = @{
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        Location          = @($Location | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() -replace '\s', '' })
        GroupBy           = $GroupBy
        Layout            = $Layout
        NetworkOnly       = [bool]$NetworkOnly
        ExcludeType       = @($ExcludeType | Where-Object { $_ })
        Title             = $Title
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

    Write-AACRule -Title 'Azure Admin Console :: Network topology' -Color 'deepskyblue3_1'
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
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
        $map = ConvertTo-AACResourceMap -Resource $resources.ToArray() -External $external.ToArray() -SubscriptionName $subscriptionNames -IconType $asset.Icons.types -IconLabel $labels -ExcludeType $request.ExcludeType
        $map = ConvertTo-AACNetworkTopology -Map $map -Resource (@($resources) + @($external)) -Subscription $subscriptions -GroupBy $request.GroupBy
        $stats = $map.Stats
        Update-AACProgress -Id 'map' -Complete -Description ('{0:N0} network(s): {1:N0} hub(s), {2:N0} spoke(s); {3:N0} peering(s), {4:N0} connection(s)' -f $stats.Networks, $stats.Hubs, $stats.Spokes, $stats.Peerings, $stats.Connections)

        $scopeText = if ($request.ManagementGroupId.Count) { "management group $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { @($request.SubscriptionId | ForEach-Object { if ($subscriptionNames.Contains($_.ToLowerInvariant())) { $subscriptionNames[$_.ToLowerInvariant()] } else { $_ } }) -join ', ' } else { 'every subscription you can see' }
        if ($request.Location.Count) { $scopeText += " ($($request.Location -join ', '))" }
        $mapTitle = if ($request.Title) { $request.Title } else { "Network topology: $scopeText" }
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
        $layoutName = switch ($request.Layout) { 'HubSpoke' { 'hubspoke' } 'Hierarchy' { 'packed' } default { if ($map.Layout -eq 'hubspoke') { 'hubspoke' } else { 'packed' } } }
        Update-AACProgress -Id 'html' -Indeterminate -Description 'Writing the diagram'
        Write-AACResourceMapHtml -Map $map -Path $htmlFullPath -Title $mapTitle -Fact $facts -Direction $(if ($Direction -eq 'TopToBottom') { 'DOWN' } else { 'RIGHT' }) -Theme $Theme.ToLowerInvariant() -NsgView $NsgView.ToLowerInvariant() -Layout $layoutName -Hierarchy packed
        Update-AACProgress -Id 'html' -Complete -Description "Diagram: $htmlFullPath"
        @{ Map = $map; Title = $mapTitle }
    }

    # --- At the prompt: tiles, hubs and their spokes, findings --------------------------------------
    $map = $state.Map
    $stats = $map.Stats
    $glyph = Get-AACGlyph
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    if (-not $stats.Networks -and -not $stats.VirtualHubs) {
        Write-AACMarkup '[grey58]No virtual networks were found in that scope; the diagram is empty.[/]'
    }
    else {
        Show-AACTileRow -Tile @(
            @{ Value = '{0:N0}' -f $stats.Networks; Caption = 'virtual networks'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $stats.Hubs; Caption = 'hubs'; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f $stats.Spokes; Caption = 'spokes'; Color = 'deepskyblue1' }
            @{ Value = '{0:N0}' -f $stats.Peerings; Caption = 'peerings'; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f ($stats.Firewalls + $stats.Appliances); Caption = 'firewalls and appliances'; Color = 'red1' }
            @{ Value = '{0:N0}' -f $stats.Gateways; Caption = 'gateways'; Color = 'gold1' }
        )
        [Spectre.Console.AnsiConsole]::WriteLine()
        $vnets = @($map.Clusters | Where-Object { $_.kind -eq 'vnet' })
        $hubs = @($vnets | Where-Object { $_.role -eq 'hub' } | Sort-Object -Property { $_.name })
        if ($hubs.Count) {
            $table = [Spectre.Console.Table]::new()
            $table.Border = [Spectre.Console.TableBorder]::Rounded
            $table.BorderStyle = [Spectre.Console.Style]::Parse('mediumpurple2')
            $table.Title = [Spectre.Console.TableTitle]::new("[bold mediumpurple2]$($glyph.Bullet) Hubs and their spokes[/]")
            foreach ($header in 'Hub', 'Where', 'Transit', 'Spokes') { $null = $table.AddColumn([Spectre.Console.TableColumn]::new("[grey62]$header[/]")) }
            foreach ($hub in $hubs) {
                $inside = @($map.Nodes | Where-Object { $_.parent -and ($_.parent -eq $hub.id -or $_.parent -like "$($hub.id)/subnets/*") -and ($_.type -in 'microsoft.network/azurefirewalls', 'microsoft.network/virtualnetworkgateways', 'microsoft.network/vpngateways', 'microsoft.network/expressroutegateways' -or $_.nva) } | ForEach-Object { "$($_.name) ($($_.typeLabel))" })
                $spokes = @($vnets | Where-Object { $_.role -eq 'spoke' -and $_.hub -eq $hub.id } | ForEach-Object { $_.name } | Sort-Object)
                $cells = @(
                    "[bold]$(& $escape $hub.name)[/]$(if ($hub.external) { ' [grey50](outside the scope)[/]' })"
                    "[grey70]$(& $escape $hub.context)[/]"
                    $(if ($inside.Count) { & $escape ($inside -join ', ') } else { '[grey50]-[/]' })
                    "[deepskyblue1]$($spokes.Count)[/] [grey58]$(& $escape (($spokes | Select-Object -First 8) -join ', '))$(if ($spokes.Count -gt 8) { ", +$($spokes.Count - 8) more" })[/]"
                )
                [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
            }
            [Spectre.Console.AnsiConsole]::Write($table)
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        $findings = @($map.Findings)
        if ($findings.Count) {
            $colors = @{ High = 'red1'; Medium = 'orange1'; Info = 'grey62' }
            Write-AACMarkup "[bold]Findings[/] [grey58]($($findings.Count))[/]"
            foreach ($group in @($findings | Group-Object -Property Severity, Finding)) {
                $first = $group.Group[0]
                $names = @($group.Group | ForEach-Object { $_.Resource } | Select-Object -Unique)
                Write-AACMarkup "  [$($colors[$first.Severity])]$($first.Severity.ToUpperInvariant())[/] $(& $escape $first.Finding) [grey58]($($group.Count)): $(& $escape (($names | Select-Object -First 6) -join ', '))$(if ($names.Count -gt 6) { ", +$($names.Count - 6) more" })[/]"
            }
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
    }
    if (-not $NoBrowser) {
        Open-AACFile -Path $htmlFullPath
        Write-AACMarkup '[grey58]Opened in your browser: switch between Hub & spoke and Hierarchy at the top; Save PNG, JPEG or SVG there too.[/]'
    }
    else { Write-AACMarkup "[grey58]Diagram: $(& $escape $htmlFullPath)[/]" }

    if ($PassThru) {
        [pscustomobject]@{
            PSTypeName = 'AAC.NetworkTopology'
            Title      = $state.Title
            Path       = $htmlFullPath
            Networks   = @($map.Clusters | Where-Object { $_.kind -eq 'vnet' } | ForEach-Object {
                    $hubId = $_.hub
                    [pscustomobject]@{
                        PSTypeName = 'AAC.NetworkTopologyNetwork'
                        Name = $_.name; Role = $_.role; Hub = $(if ($_.hub) { (@($map.Clusters | Where-Object { $_.id -eq $hubId } | ForEach-Object { $_.name }) | Select-Object -First 1) } else { '' }); Peerings = [int]$_.peerCount
                        Where = $_.context; AddressSpace = (@($_.detail | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+/' }) | Select-Object -First 1); Outside = [bool]$_.external; Id = $_.id
                    }
                })
            Findings   = @($map.Findings)
            Nodes      = @($map.Nodes | ForEach-Object { [pscustomobject]@{ Name = $_.name; Type = $_.type; Product = $_.typeLabel; Appliance = [bool]$_.nva; Parent = $_.parent; Details = ($_.facts -join ' · '); Outside = $_.external; Id = $_.id } })
            Edges      = @($map.Edges | ForEach-Object { [pscustomobject]@{ Kind = $_.kind; Source = $_.source; Target = $_.target; Label = $_.label; Warning = [bool]$_.warn } })
            Stats      = [pscustomobject]$stats
        }
    }
}
