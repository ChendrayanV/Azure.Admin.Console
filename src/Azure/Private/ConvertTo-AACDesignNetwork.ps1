function ConvertTo-AACDesignNetwork {
    <#
    .SYNOPSIS
        Plans a hub and spoke network and the resources in it, for
        New-AACDesignDiagram: the subnets and their address ranges, the names,
        the routes and the private endpoints, as a map model for
        ConvertTo-AACDrawio and the rows for the reports.
    .DESCRIPTION
        No Azure calls: nothing here exists yet. -Hub is @{ AddressSpace;
        Subscription; ResourceGroup; Firewall; Bastion; VpnGateway }, and -Spoke
        a list of @{ Name; AddressSpace; Subscription; ResourceGroup; Resources;
        Subnets } (already checked by the command).

        Subnets come from each network's address space, largest first so nothing
        is left stranded, at the size Microsoft recommends for what is in them -
        or the smallest it supports, when the space is too tight - and are listed
        in address order. A spoke's own Subnets are kept as given, and must sit
        inside its space without overlapping. A network too small for its subnets,
        or networks that overlap, stop the command: a diagram of addresses that
        can't exist would mislead.

        With a firewall, each spoke gets a route table sending 0.0.0.0/0 to the
        firewall's private IP (the fourth address of AzureFirewallSubnet, the
        first Azure leaves free), and its subnets use it. Every spoke is peered
        with the hub; with a VPN gateway, the peering uses its transit. Private
        DNS zones for the private endpoints are drawn in the hub, as the landing
        zone pattern has them.

        Returns @{ Map (Clusters, Nodes, Edges); Subnets (AAC.DesignSubnet);
        Resources (AAC.DesignResource); Facts }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Region,

        [Parameter(Mandatory)]
        [string] $Environment,

        [Parameter(Mandatory)]
        [hashtable] $Hub,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Spoke
    )

    $catalogue = Get-AACDesignResource
    $code = Get-AACRegionCode -Region $Region
    $stage = $Environment.ToLowerInvariant()
    $named = { param([string] $Abbreviation, [string] $Workload, [switch] $NoHyphen) $text = "$Abbreviation-$Workload-$stage-$code".ToLowerInvariant(); if ($NoHyphen) { $text -replace '-', '' } else { $text } }
    $toText = { param([long] $Value) '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255) }
    $parse = {
        param([string] $Prefix, [string] $What)
        $range = ConvertTo-AACCidrRange -Prefix $Prefix
        if (-not $range.Valid -or $range.Version -ne 4) { throw "Azure Admin Console can't use '$Prefix' for $What`: give an IPv4 range such as 10.1.0.0/16." }
        # The parser keeps only the network part, so compare the address as written with where the range starts.
        $bytes = [System.Net.IPAddress]::Parse(($Prefix -split '/')[0]).GetAddressBytes()
        $written = ([long]$bytes[0] -shl 24) + ([long]$bytes[1] -shl 16) + ([long]$bytes[2] -shl 8) + [long]$bytes[3]
        if ($written -ne $range.Start -or $range.Start % $range.Size) { throw "Azure Admin Console can't use '$Prefix' for $What`: it doesn't start on a /$($range.Length) boundary. Use $(& $toText ($range.Start - $range.Start % $range.Size))/$($range.Length)." }
        $range
    }
    # Each subnet kind: its name, and the prefix lengths recommended and accepted.
    $kinds = [ordered]@{
        firewall         = @{ Name = 'AzureFirewallSubnet'; Preferred = 26; Minimum = 26; Nsg = $false; Route = $false; Note = 'Azure Firewall needs a /26' }
        bastion          = @{ Name = 'AzureBastionSubnet'; Preferred = 26; Minimum = 26; Nsg = $false; Route = $false; Note = 'Azure Bastion needs a /26' }
        gateway          = @{ Name = 'GatewaySubnet'; Preferred = 27; Minimum = 27; Nsg = $false; Route = $false; Note = '/27 or larger for a VPN gateway' }
        aks              = @{ Name = 'snet-aks'; Preferred = 22; Minimum = 24; Nsg = $true; Route = $true; Note = 'nodes; Azure CNI Overlay assumed, so pods take no subnet IPs' }
        appgw            = @{ Name = 'snet-appgw'; Preferred = 24; Minimum = 26; Nsg = $true; Route = $false; Note = 'Application Gateway v2, the subnet its own' }
        workload         = @{ Name = 'snet-workload'; Preferred = 24; Minimum = 27; Nsg = $true; Route = $true; Note = '' }
        integration      = @{ Name = 'snet-integration'; Preferred = 26; Minimum = 28; Nsg = $true; Route = $true; Note = 'delegated to Microsoft.Web/serverFarms' }
        apim             = @{ Name = 'snet-apim'; Preferred = 27; Minimum = 29; Nsg = $true; Route = $false; Note = 'API Management, injected' }
        privateendpoints = @{ Name = 'snet-privateendpoints'; Preferred = 26; Minimum = 28; Nsg = $true; Route = $false; Note = 'private endpoints' }
    }
    # Largest first, so smaller subnets fill the gaps; then the plan reads in address order.
    $allocate = {
        param($Range, [object[]] $Wanted, [string] $NetworkName)
        foreach ($tier in 'Preferred', 'Minimum') {
            $cursor = [long]$Range.Start
            $placed = [System.Collections.Generic.List[object]]::new()
            $fits = $true
            # Same-sized subnets keep the catalogue's order, so a design comes out the same every time.
            foreach ($item in @($Wanted | Sort-Object -Property @{ Expression = { $kinds[$_].$tier } }, @{ Expression = { @($kinds.Keys).IndexOf($_) } })) {
                $size = [long][Math]::Pow(2, 32 - $kinds[$item].$tier)
                $start = [long]([Math]::Ceiling($cursor / $size) * $size)
                if ($start + $size -gt $Range.Start + $Range.Size) { $fits = $false; break }
                $placed.Add(@{ Kind = $item; Prefix = "$(& $toText $start)/$($kinds[$item].$tier)"; Start = $start; Size = $size })
                $cursor = $start + $size
            }
            if ($fits) { return @($placed | Sort-Object -Property Start) }
        }
        $need = ($Wanted | ForEach-Object { [Math]::Pow(2, 32 - $kinds[$_].Minimum) } | Measure-Object -Sum).Sum
        throw "Azure Admin Console can't fit $NetworkName's subnets ($(@($Wanted | ForEach-Object { $kinds[$_].Name }) -join ', ')) in $($Range.Prefix): even at their smallest they need $need addresses. Give it a larger address space."
    }

    $clusters = [System.Collections.Generic.List[object]]::new()
    $nodes = [System.Collections.Generic.List[object]]::new()
    $edges = [System.Collections.Generic.List[object]]::new()
    $subnetRows = [System.Collections.Generic.List[object]]::new()
    $resourceRows = [System.Collections.Generic.List[object]]::new()
    $taken = [System.Collections.Generic.List[object]]::new()
    $zones = [System.Collections.Generic.HashSet[string]]::new()
    $scope = {
        param([string] $Subscription, [string] $Group)
        $subId = "design/subscription/$Subscription"
        if (-not @($clusters | Where-Object { $_.id -eq $subId }).Count) {
            $clusters.Add([ordered]@{ id = $subId; name = $Subscription; kind = 'subscription'; icon = 'subscription'; parent = ''; detail = @('planned') })
            $clusters.Add([ordered]@{ id = "$subId/region"; name = $Region; kind = 'region'; icon = 'resource'; parent = $subId })
        }
        $groupId = "design/resourcegroup/$Group"
        if (-not @($clusters | Where-Object { $_.id -eq $groupId }).Count) { $clusters.Add([ordered]@{ id = $groupId; name = $Group; kind = 'resourcegroup'; icon = 'resourcegroup'; parent = "$subId/region"; detail = @('planned, not deployed') }) }
        $groupId
    }
    $node = {
        param([string] $Id, [string] $NodeName, [string] $Type, [string] $Icon, [string] $Parent, [string] $TypeLabel, [string] $Group, [string] $Subscription, [string[]] $Facts = @())
        $nodes.Add([ordered]@{ id = "design/node/$Id"; name = $NodeName; type = $Type; icon = $Icon; parent = $Parent; typeLabel = $TypeLabel; location = $Region; resourceGroup = $Group; subscription = $Subscription; facts = $Facts })
        "design/node/$Id"
    }
    $network = {
        param([string] $VnetName, $Range, [object[]] $Planned, [string] $Group, [string] $Subscription, [string] $RouteTable, [string] $NextHop)
        foreach ($other in $taken) {
            if ($Range.Start -lt $other.Start + $other.Size -and $other.Start -lt $Range.Start + $Range.Size) { throw "Azure Admin Console can't draw $VnetName at $($Range.Prefix): it overlaps $($other.Name) ($($other.Prefix)). Peered networks need address spaces of their own." }
        }
        $taken.Add(@{ Name = $VnetName; Prefix = $Range.Prefix; Start = $Range.Start; Size = $Range.Size })
        $vnetId = "design/vnet/$VnetName"
        $clusters.Add([ordered]@{ id = $vnetId; name = $VnetName; kind = 'vnet'; icon = 'vnet'; parent = (& $scope $Subscription $Group); detail = @($Range.Prefix) })
        $ids = @{}
        foreach ($subnet in $Planned) {
            $spec = $kinds[$subnet.Kind]
            $subnetName = if ($subnet.Contains('Name') -and $subnet.Name) { $subnet.Name } else { $spec.Name }
            $nsg = if ($spec.Nsg) { "nsg-$subnetName-$stage-$code" -replace 'snet-', '' } else { '' }
            $route = if ($spec.Route -and $RouteTable) { $RouteTable } else { '' }
            $usable = [Math]::Max(0, $subnet.Size - 5)
            $subnetId = "design/subnet/$VnetName/$subnetName"
            $clusters.Add([ordered]@{ id = $subnetId; name = $subnetName; kind = 'subnet'; icon = 'subnet'; parent = $vnetId; detail = @($subnet.Prefix, "$usable usable", $nsg, $(if ($route) { "route: $route" })) | Where-Object { $_ } })
            $ids[$subnet.Kind] = $subnetId
            $subnetRows.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.DesignSubnet'; Subscription = $Subscription; ResourceGroup = $Group; VirtualNetwork = $VnetName; AddressSpace = $Range.Prefix; Subnet = $subnetName; AddressPrefix = $subnet.Prefix
                    Addresses = $subnet.Size; Usable = $usable; NetworkSecurityGroup = $nsg; RouteTable = $route; NextHop = $(if ($route) { $NextHop } else { '' }); Purpose = $(if ($subnet.Contains('Purpose')) { $subnet.Purpose } else { $spec.Note })
                })
        }
        @{ Id = $vnetId; Subnets = $ids }
    }

    # --- The hub --------------------------------------------------------------------------------------------------------------
    $hubRange = & $parse $Hub.AddressSpace 'the hub'
    $hubWanted = @(if ($Hub.Firewall) { 'firewall' }; if ($Hub.Bastion) { 'bastion' }; if ($Hub.VpnGateway) { 'gateway' })
    $hubVnet = & $named 'vnet' 'hub'
    $hubPlan = if ($hubWanted.Count) { @(& $allocate $hubRange $hubWanted $hubVnet) } else { @() }
    $firewallIp = ''
    if ($Hub.Firewall) { $firewallIp = & $toText ((@($hubPlan | Where-Object Kind -EQ 'firewall')[0]).Start + 4) }
    $hubNet = & $network $hubVnet $hubRange $hubPlan $Hub.ResourceGroup $Hub.Subscription '' ''
    $hubGroup = "design/resourcegroup/$($Hub.ResourceGroup)"
    $firewallNode = ''
    if ($Hub.Firewall) {
        $firewallNode = & $node 'firewall' (& $named 'afw' 'hub') 'Microsoft.Network/azureFirewalls' 'firewall' $hubNet.Subnets.firewall 'Azure Firewall' $Hub.ResourceGroup $Hub.Subscription @("private IP $firewallIp", 'Standard or Premium')
        $policy = & $node 'firewallpolicy' (& $named 'afwp' 'hub') 'Microsoft.Network/firewallPolicies' 'firewallpolicy' $hubGroup 'Firewall policy' $Hub.ResourceGroup $Hub.Subscription
        $edges.Add([ordered]@{ source = $policy; target = $firewallNode; kind = 'dependency'; label = 'rules' })
        $resourceRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DesignResource'; Name = (& $named 'afw' 'hub'); Kind = 'Azure Firewall'; Network = $hubVnet; Subnet = 'AzureFirewallSubnet'; Access = "Private IP $firewallIp"; ResourceGroup = $Hub.ResourceGroup; Subscription = $Hub.Subscription })
    }
    if ($Hub.Bastion) {
        $null = & $node 'bastion' (& $named 'bas' 'hub') 'Microsoft.Network/bastionHosts' 'bastion' $hubNet.Subnets.bastion 'Azure Bastion' $Hub.ResourceGroup $Hub.Subscription
        $resourceRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DesignResource'; Name = (& $named 'bas' 'hub'); Kind = 'Azure Bastion'; Network = $hubVnet; Subnet = 'AzureBastionSubnet'; Access = 'In the subnet'; ResourceGroup = $Hub.ResourceGroup; Subscription = $Hub.Subscription })
    }
    if ($Hub.VpnGateway) {
        $gateway = & $node 'vpngateway' (& $named 'vpng' 'hub') 'Microsoft.Network/virtualNetworkGateways' 'vnetgateway' $hubNet.Subnets.gateway 'VPN gateway' $Hub.ResourceGroup $Hub.Subscription
        $site = [ordered]@{ id = 'design/node/onpremises'; name = 'On-premises'; type = 'Microsoft.Network/localNetworkGateways'; icon = 'localgateway'; parent = ''; typeLabel = 'Your network'; facts = @() }
        $nodes.Add($site)
        $edges.Add([ordered]@{ source = $gateway; target = $site.id; kind = 'network'; label = 'site-to-site VPN' })
        $resourceRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DesignResource'; Name = (& $named 'vpng' 'hub'); Kind = 'VPN gateway'; Network = $hubVnet; Subnet = 'GatewaySubnet'; Access = 'In the subnet'; ResourceGroup = $Hub.ResourceGroup; Subscription = $Hub.Subscription })
    }

    # --- The spokes -------------------------------------------------------------------------------------------------------------
    foreach ($item in $Spoke) {
        $spokeName = $item.Name.ToLowerInvariant()
        $range = & $parse $item.AddressSpace "spoke '$spokeName'"
        $vnetName = & $named 'vnet' $spokeName
        $neededKinds = @($item.Resources | ForEach-Object { $catalogue[$_].Subnet } | Select-Object -Unique)
        $routeTable = if ($Hub.Firewall) { & $named 'rt' $spokeName } else { '' }
        if (@($item.Subnets).Count) {
            # The architect's own subnets: kept as given, each checked.
            $plan = @(foreach ($given in $item.Subnets) {
                    $subnetRange = & $parse $given.AddressPrefix "subnet '$($given.Name)' of spoke '$spokeName'"
                    if ($subnetRange.Start -lt $range.Start -or $subnetRange.Start + $subnetRange.Size -gt $range.Start + $range.Size) { throw "Azure Admin Console can't place subnet '$($given.Name)' ($($given.AddressPrefix)) in spoke '$spokeName': it isn't inside $($range.Prefix)." }
                    $holds = @($given.Resources | ForEach-Object { $catalogue[$_].Subnet } | Select-Object -Unique)
                    @{ Kind = $(if ($holds.Count) { $holds[0] } else { 'workload' }); Name = $given.Name; Prefix = $given.AddressPrefix; Start = $subnetRange.Start; Size = $subnetRange.Size; Purpose = "your subnet$(if ($given.Resources) { ': ' + (@($given.Resources) -join ', ') })"; Holds = @($given.Resources) }
                })
            for ($i = 0; $i -lt $plan.Count; $i++) {
                for ($j = $i + 1; $j -lt $plan.Count; $j++) {
                    if ($plan[$i].Start -lt $plan[$j].Start + $plan[$j].Size -and $plan[$j].Start -lt $plan[$i].Start + $plan[$i].Size) { throw "Azure Admin Console can't use subnets '$($plan[$i].Name)' and '$($plan[$j].Name)' in spoke '$spokeName': their ranges overlap." }
                }
            }
            $missing = @($neededKinds | Where-Object { $kind = $_; -not @($plan | Where-Object { $_.Kind -eq $kind }).Count })
            if ($missing.Count) { throw "Azure Admin Console has nowhere to put spoke '$spokeName''s $(@($item.Resources | Where-Object { $catalogue[$_].Subnet -in $missing }) -join ', '): list them in one of its Subnets, or leave Subnets out to have them planned." }
            $plan = @($plan | Sort-Object -Property Start)
        }
        else { $plan = @(& $allocate $range $neededKinds $vnetName) }
        $spokeNet = & $network $vnetName $range $plan $item.ResourceGroup $item.Subscription $routeTable $firewallIp
        $groupId = "design/resourcegroup/$($item.ResourceGroup)"
        $edges.Add([ordered]@{ source = $hubNet.Id; target = $spokeNet.Id; kind = 'peering'; label = $(if ($Hub.VpnGateway) { 'peering, gateway transit' } else { 'peering' }) })
        if ($routeTable) {
            $routeNode = & $node "rt/$spokeName" $routeTable 'Microsoft.Network/routeTables' 'routetable' $groupId 'Route table' $item.ResourceGroup $item.Subscription @("0.0.0.0/0 to $firewallIp")
            $edges.Add([ordered]@{ source = $routeNode; target = $firewallNode; kind = 'route'; label = "0.0.0.0/0 next hop $firewallIp" })
        }
        $plans = @{}
        $count = @{}
        foreach ($key in $item.Resources) {
            $entry = $catalogue[$key]
            $count[$key] = 1 + $(if ($count.ContainsKey($key)) { $count[$key] } else { 0 })
            $resourceName = (& $named $entry.Abbreviation $spokeName -NoHyphen:([bool]$entry.Contains('NoHyphen'))) + $(if ($count[$key] -gt 1) { "-{0:D2}" -f $count[$key] } else { '' })
            $subnetId = $spokeNet.Subnets[$entry.Subnet]
            $subnetName = ($subnetId -split '/')[-1]
            switch ($entry.Access) {
                'Integration' {
                    $planKey = 'plan'
                    if (-not $plans.ContainsKey($planKey)) { $plans[$planKey] = & $node "plan/$spokeName" (& $named 'asp' $spokeName) 'Microsoft.Web/serverFarms' 'appserviceplan' $groupId 'App Service plan' $item.ResourceGroup $item.Subscription @('Premium v3 for VNet integration') }
                    $app = & $node "$spokeName/$resourceName" $resourceName $entry.Type $entry.Icon $groupId $entry.Label $item.ResourceGroup $item.Subscription @("VNet integration: $subnetName")
                    $edges.Add([ordered]@{ source = $app; target = $plans[$planKey]; kind = 'dependency'; label = 'runs on' })
                    $edges.Add([ordered]@{ source = $app; target = $subnetId; kind = 'network'; label = 'VNet integration' })
                    $access = "VNet integration through $subnetName"
                }
                'PrivateEndpoint' {
                    $service = & $node "$spokeName/$resourceName" $resourceName $entry.Type $entry.Icon $groupId $entry.Label $item.ResourceGroup $item.Subscription @('public network access off')
                    $endpoint = & $node "$spokeName/pe-$resourceName" "pe-$resourceName" 'Microsoft.Network/privateEndpoints' 'privateendpoint' $subnetId 'Private endpoint' $item.ResourceGroup $item.Subscription @($entry.Zone)
                    $edges.Add([ordered]@{ source = $endpoint; target = $service; kind = 'privatelink'; label = 'private link' })
                    [void]$zones.Add($entry.Zone)
                    $access = "Private endpoint in $subnetName"
                }
                default {
                    $null = & $node "$spokeName/$resourceName" $resourceName $entry.Type $entry.Icon $subnetId $entry.Label $item.ResourceGroup $item.Subscription
                    $access = "In $subnetName"
                }
            }
            $resourceRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.DesignResource'; Name = $resourceName; Kind = $entry.Label; Network = $vnetName; Subnet = $subnetName; Access = $access; ResourceGroup = $item.ResourceGroup; Subscription = $item.Subscription })
        }
    }

    # The private DNS zones the private endpoints resolve through, linked to the hub.
    foreach ($zone in @($zones | Sort-Object)) {
        $zoneNode = & $node "zone/$zone" $zone 'Microsoft.Network/privateDnsZones' 'dnszone' $hubGroup 'Private DNS zone' $Hub.ResourceGroup $Hub.Subscription @('linked to the hub')
        $edges.Add([ordered]@{ source = $zoneNode; target = $hubNet.Id; kind = 'dns'; label = '' })
    }

    @{
        Map       = @{ Clusters = $clusters.ToArray(); Nodes = $nodes.ToArray(); Edges = $edges.ToArray() }
        Subnets   = $subnetRows.ToArray()
        Resources = $resourceRows.ToArray()
        Facts     = @(
            "Design: $Name ($stage, $Region)"
            "Hub $hubVnet $($hubRange.Prefix)$(if ($Hub.Firewall) { "; Azure Firewall at $firewallIp" })"
            "$(@($Spoke).Count) spoke(s), each peered with the hub$(if ($Hub.Firewall) { ', their traffic routed through the firewall' })"
            'Planned, not deployed: drawn by New-AACDesignDiagram'
        )
    }
}
