function ConvertTo-AACVirtualNetworkAssessment {
    <#
    .SYNOPSIS
        Assesses virtual networks from Azure Resource Graph rows: address
        space and IP capacity, subnets, peerings, NSGs and ASGs, security,
        DNS and connectivity - the model behind
        Invoke-AACVirtualNetworkAssessment.
    .DESCRIPTION
        No Azure calls - every input is Resource Graph rows (hashtables):
          -VirtualNetwork      the VNets to assess (id, name, resourceGroup,
                               subscriptionId, location, tags, properties)
          -AllNetwork          every VNet the account can see (id, name,
                               subscriptionId, location, prefixes, peers) -
                               for remote peerings and overlapping spaces
          -NetworkInterface    NICs (id, name, nsg, vm, ipForwarding,
                               privateEndpoint, ipConfigurations)
          -RouteTable, -NatGateway, -ApplicationSecurityGroup, -PublicIp,
          -PrivateEndpoint, -FlowLog, -Firewall, -Bastion,
          -Gateway, -DnsLink, -DnsResolver, -NetworkSecurityGroup (rows)
          -NsgAssessment       ConvertTo-AACNsgAssessment's result for the
                               NSGs applied in these VNets

        Returns a hashtable:
          VirtualNetworks  AAC.VirtualNetwork: metadata, address space and
                           IPs (total, in subnets, free, usable, used,
                           available), DNS, DDoS, encryption, flow logs,
                           gateways, firewalls, Bastion, peerings, role
                           (hub or spoke), findings
          Subnets          AAC.VirtualNetworkSubnet: prefixes, usable / used
                           / available IPs, NSG, route table and its default
                           route, NAT gateway, outbound path, service
                           endpoints, delegations, private endpoints and
                           their network policies, NICs, VMs, public IPs,
                           special purpose
          Peerings         AAC.VirtualNetworkPeering
          FreeRanges       AAC.VirtualNetworkFreeRange: the address space no
                           subnet uses, as CIDR blocks
          Asgs             AAC.ApplicationSecurityGroupUse: NICs in each ASG
                           and the NSG rules that name it
          PrivateEndpoints AAC.VirtualNetworkPrivateEndpoint
          Findings         AAC.VirtualNetworkFinding - by severity, with the
                           NSG assessment's findings (Source NSG)
          Stats
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $VirtualNetwork,

        [AllowEmptyCollection()] [object[]] $AllNetwork = @(),
        [AllowEmptyCollection()] [object[]] $NetworkInterface = @(),
        [AllowEmptyCollection()] [object[]] $RouteTable = @(),
        [AllowEmptyCollection()] [object[]] $NatGateway = @(),
        [AllowEmptyCollection()] [object[]] $ApplicationSecurityGroup = @(),
        [AllowEmptyCollection()] [object[]] $PublicIp = @(),
        [AllowEmptyCollection()] [object[]] $PrivateEndpoint = @(),
        [AllowEmptyCollection()] [object[]] $FlowLog = @(),
        [AllowEmptyCollection()] [object[]] $Firewall = @(),
        [AllowEmptyCollection()] [object[]] $Bastion = @(),
        [AllowEmptyCollection()] [object[]] $Gateway = @(),
        [AllowEmptyCollection()] [object[]] $DnsLink = @(),
        [AllowEmptyCollection()] [object[]] $DnsResolver = @(),
        [AllowEmptyCollection()] [object[]] $NetworkSecurityGroup = @(),
        [hashtable] $NsgAssessment,
        [hashtable] $SubscriptionName = @{}
    )

    # --- Helpers ---------------------------------------------------------------------------------------------------
    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary] -and $Value.Contains($key)) { $Value = $Value[$key] } else { return $null } }
        $Value
    }
    $lower = { param($Value) ([string]$Value).ToLowerInvariant() }
    $leaf = { param($Id) if ($Id) { ([string]$Id -split '/')[-1] } else { '' } }
    $list = { param($Value) @($Value | Where-Object { $null -ne $_ -and '' -ne $_ }) }
    $subscriptionOf = { param([string] $Id) if ($Id -match '^/subscriptions/([^/]+)') { $key = $Matches[1].ToLowerInvariant(); if ($SubscriptionName.Contains($key)) { $SubscriptionName[$key] } else { $Matches[1] } } else { '' } }
    # The VNet a subnet, NIC configuration or other child ID belongs to.
    $vnetOf = { param([string] $Id) if ($Id -match '^(.+/providers/microsoft\.network/virtualnetworks/[^/]+)') { $Matches[1].ToLowerInvariant() } else { '' } }
    $object = {
        param([string] $TypeName, [System.Collections.IDictionary] $Property)
        $item = [pscustomobject]$Property
        $item.PSObject.TypeNames.Insert(0, $TypeName)
        $item
    }
    # Measure-Object -Sum has no Sum for no input (strict mode): add up by hand.
    $sumOf = { param($Values, [string] $Name) $t = [long]0; foreach ($v in $Values) { $n = if ($Name) { $v.$Name } else { $v }; if ($null -ne $n) { $t += [long]$n } }; $t }
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $Category, [string] $Title, [string] $VirtualNetwork, [string] $Item, [string] $Detail, [string] $Action, [string] $ResourceId, [string] $Source = 'Assessment')
        $findings.Add((& $object 'AAC.VirtualNetworkFinding' ([ordered]@{ Severity = $Severity; Category = $Category; Finding = $Title; VirtualNetwork = $VirtualNetwork; Item = $Item; Detail = $Detail; Action = $Action; Source = $Source; ResourceId = $ResourceId })))
    }

    # --- Indexes ---------------------------------------------------------------------------------------------------
    $byId = { param([object[]] $Rows) $index = @{}; foreach ($row in $Rows) { if ($row -and $row['id']) { $index[(& $lower $row['id'])] = $row } }; $index }
    $routeTables = & $byId $RouteTable
    $natGateways = & $byId $NatGateway
    $publicIps = & $byId $PublicIp
    $allNetworks = & $byId $AllNetwork
    # NICs by subnet, with the facts that matter.
    $nicsBySubnet = @{}
    $asgUse = @{}
    foreach ($nic in $NetworkInterface) {
        foreach ($configuration in @($nic['ipConfigurations'] | Where-Object { $_ })) {
            $subnetId = & $lower (& $at $configuration 'properties', 'subnet', 'id')
            if (-not $subnetId) { continue }
            if (-not $nicsBySubnet.Contains($subnetId)) { $nicsBySubnet[$subnetId] = [System.Collections.Generic.List[object]]::new() }
            $publicId = & $lower (& $at $configuration 'properties', 'publicIPAddress', 'id')
            $nicsBySubnet[$subnetId].Add(@{ Nic = $nic; Vm = [string]$nic['vm']; PublicIp = $publicId; Ip = [string](& $at $configuration 'properties', 'privateIPAddress'); Forwarding = [bool]$nic['ipForwarding']; PrivateEndpoint = [string]$nic['privateEndpoint'] })
            foreach ($asg in @(& $at $configuration 'properties', 'applicationSecurityGroups')) {
                $asgId = & $lower (& $at $asg 'id')
                if (-not $asgId) { continue }
                if (-not $asgUse.Contains($asgId)) { $asgUse[$asgId] = [System.Collections.Generic.List[object]]::new() }
                $asgUse[$asgId].Add(@{ Nic = [string]$nic['name']; Vm = & $leaf $nic['vm']; VirtualNetwork = & $vnetOf $subnetId })
            }
        }
    }
    $inVnet = {
        param([object[]] $Rows, [string] $VnetId)
        @($Rows | Where-Object { $_ -and @(@(& $at $_ 'ipConfigurations') + @(& $at $_ 'properties', 'ipConfigurations') | Where-Object { $_ } | Where-Object { (& $vnetOf (& $at $_ 'properties', 'subnet', 'id')) -eq $VnetId -or (& $vnetOf (& $at $_ 'subnet')) -eq $VnetId }).Count })
    }
    $flowTargets = @{}
    foreach ($log in $FlowLog) { $target = & $lower $log['target']; if ($target -and $false -ne $log['enabled']) { $flowTargets[$target] = $log } }
    $special = @{ 'gatewaysubnet' = 'Gateway'; 'azurefirewallsubnet' = 'Azure Firewall'; 'azurefirewallmanagementsubnet' = 'Azure Firewall management'; 'azurebastionsubnet' = 'Azure Bastion'; 'routeserversubnet' = 'Route Server' }
    # The smallest prefix each special subnet needs, and whether an NSG is allowed on it.
    $sizing = @{ 'gatewaysubnet' = 27; 'azurefirewallsubnet' = 26; 'azurefirewallmanagementsubnet' = 26; 'azurebastionsubnet' = 26; 'routeserversubnet' = 27 }
    $privateZones = @{ blob = 'privatelink.blob.core.windows.net'; blob_secondary = 'privatelink.blob.core.windows.net'; file = 'privatelink.file.core.windows.net'; queue = 'privatelink.queue.core.windows.net'; table = 'privatelink.table.core.windows.net'; dfs = 'privatelink.dfs.core.windows.net'; web = 'privatelink.web.core.windows.net'; vault = 'privatelink.vaultcore.azure.net'; sqlserver = 'privatelink.database.windows.net'; registry = 'privatelink.azurecr.io'; sites = 'privatelink.azurewebsites.net'; namespace = 'privatelink.servicebus.windows.net'; account = 'privatelink.cognitiveservices.azure.com'; sql = 'privatelink.documents.azure.com'; mongodb = 'privatelink.mongo.cosmos.azure.com'; rediscache = 'privatelink.redis.cache.windows.net'; searchservice = 'privatelink.search.windows.net'; postgresqlserver = 'privatelink.postgres.database.azure.com'; mysqlserver = 'privatelink.mysql.database.azure.com'; configurationstores = 'privatelink.azconfig.io' }

    $vnets = [System.Collections.Generic.List[object]]::new()
    $subnets = [System.Collections.Generic.List[object]]::new()
    $peerings = [System.Collections.Generic.List[object]]::new()
    $free = [System.Collections.Generic.List[object]]::new()
    $endpoints = [System.Collections.Generic.List[object]]::new()
    $scoped = @{}
    foreach ($vnet in $VirtualNetwork) { $scoped[(& $lower $vnet['id'])] = $true }

    foreach ($vnet in $VirtualNetwork) {
        $vnetId = & $lower $vnet['id']
        $name = [string]$vnet['name']
        $properties = & $at $vnet 'properties'
        $space = @(& $list (& $at $properties 'addressSpace', 'addressPrefixes'))
        $spaceRanges = @($space | ForEach-Object { ConvertTo-AACCidrRange $_ })
        $total = & $sumOf @($spaceRanges | Where-Object { $_.Version -eq 4 -and $_.Valid }) 'Size'
        $dns = @(& $list (& $at $properties 'dhcpOptions', 'dnsServers'))
        $links = @($DnsLink | Where-Object { (& $lower $_['vnet']) -eq $vnetId })
        $zoneNames = @($links | ForEach-Object { ([string]$_['zone']).ToLowerInvariant() })
        $gateways = @(& $inVnet $Gateway $vnetId)
        $firewalls = @(& $inVnet $Firewall $vnetId)
        $bastions = @(& $inVnet $Bastion $vnetId)
        $resolvers = @($DnsResolver | Where-Object { (& $lower $_['vnet']) -eq $vnetId })
        $planId = & $lower (& $at $properties 'ddosProtectionPlan', 'id')
        $ddosOn = [bool](& $at $properties 'enableDdosProtection') -and $planId
        $encryption = & $at $properties 'encryption'
        $vnetFlowLog = $flowTargets[$vnetId]

        # --- Subnets ---------------------------------------------------------------------------------------------
        $vnetSubnets = [System.Collections.Generic.List[object]]::new()
        $usedPrefixes = [System.Collections.Generic.List[string]]::new()
        $publicIpCount = 0
        foreach ($subnet in @(& $at $properties 'subnets' | Where-Object { $_ })) {
            $subnetId = & $lower $subnet['id']
            $subnetName = [string]$subnet['name']
            $sp = & $at $subnet 'properties'
            $prefixes = @(& $list $(if (& $at $sp 'addressPrefix') { & $at $sp 'addressPrefix' } else { & $at $sp 'addressPrefixes' }))
            foreach ($prefix in $prefixes) { $usedPrefixes.Add([string]$prefix) }
            $ranges = @($prefixes | ForEach-Object { ConvertTo-AACCidrRange $_ } | Where-Object { $_.Version -eq 4 -and $_.Valid })
            $size = & $sumOf $ranges 'Size'
            $usable = & $sumOf @($ranges | ForEach-Object { [Math]::Max(0, $_.Size - 5) })
            $used = @(& $at $sp 'ipConfigurations' | Where-Object { $_ }).Count
            $delegations = @(@(& $at $sp 'delegations') | Where-Object { $_ } | ForEach-Object { [string](& $at $_ 'properties', 'serviceName') })
            $nics = @(if ($nicsBySubnet.Contains($subnetId)) { $nicsBySubnet[$subnetId] })
            $computeNics = @($nics | Where-Object { -not $_.PrivateEndpoint })
            $vms = @($computeNics | Where-Object Vm | ForEach-Object { $_.Vm } | Select-Object -Unique)
            $withPublicIp = @($computeNics | Where-Object PublicIp)
            $publicIpCount += $withPublicIp.Count
            $nsgId = & $lower (& $at $sp 'networkSecurityGroup', 'id')
            $routeTableId = & $lower (& $at $sp 'routeTable', 'id')
            $table = if ($routeTableId) { $routeTables[$routeTableId] } else { $null }
            $routes = @(@(if ($table) { & $at $table 'routes' }) | Where-Object { $_ })
            $defaultRoute = $routes | Where-Object { [string](& $at $_ 'properties', 'addressPrefix') -eq '0.0.0.0/0' } | Select-AACFirst 1
            $defaultHop = if ($defaultRoute) { "$(& $at $defaultRoute 'properties', 'nextHopType')$(if (& $at $defaultRoute 'properties', 'nextHopIpAddress') { " $(& $at $defaultRoute 'properties', 'nextHopIpAddress')" })" } else { '' }
            $natId = & $lower (& $at $sp 'natGateway', 'id')
            $defaultOutbound = & $at $sp 'defaultOutboundAccess'
            $purpose = $special[$subnetName.ToLowerInvariant()]
            $peCount = @(& $at $sp 'privateEndpoints' | Where-Object { $_ }).Count
            $outbound = if ($purpose) { '' }
            elseif ($natId) { 'NAT gateway' }
            elseif ($defaultRoute -and [string](& $at $defaultRoute 'properties', 'nextHopType') -eq 'VirtualAppliance') { 'Firewall / NVA (route table)' }
            elseif ($defaultRoute -and [string](& $at $defaultRoute 'properties', 'nextHopType') -eq 'VirtualNetworkGateway') { 'Forced tunnelling (gateway)' }
            elseif ($defaultRoute -and [string](& $at $defaultRoute 'properties', 'nextHopType') -eq 'None') { 'None (route drops it)' }
            elseif ($false -eq $defaultOutbound) { 'None (private subnet)' }
            elseif ($computeNics.Count -and $withPublicIp.Count -eq $computeNics.Count) { 'Public IPs on NICs' }
            elseif ($computeNics.Count) { 'Default outbound access' }
            else { '' }
            $subnetFlow = if ($flowTargets.Contains($subnetId)) { 'Subnet flow log' } elseif ($vnetFlowLog) { 'VNet flow log' } elseif ($nsgId -and $flowTargets.Contains($nsgId)) { 'NSG flow log' } else { 'None' }
            $row = & $object 'AAC.VirtualNetworkSubnet' ([ordered]@{
                    VirtualNetwork          = $name
                    Subnet                  = $subnetName
                    Purpose                 = $(if ($purpose) { $purpose } elseif ($delegations.Count) { "Delegated: $($delegations -join ', ')" } elseif ($peCount -and -not $computeNics.Count) { 'Private endpoints' } else { 'Workloads' })
                    Prefix                  = $prefixes -join ', '
                    Size                    = $size
                    Usable                  = $usable
                    Used                    = $used
                    Available               = [Math]::Max(0, $usable - $used)
                    UsedPercent             = $(if ($usable) { [Math]::Round($used / $usable * 100, 1) } else { $null })
                    Nsg                     = & $leaf $nsgId
                    RouteTable              = & $leaf $routeTableId
                    DefaultRoute            = $defaultHop
                    BgpPropagation          = $(if ($table) { $(if (& $at $table 'disableBgpRoutePropagation') { 'Disabled' } else { 'Enabled' }) } else { '' })
                    NatGateway              = $(if ($natId) { "$(& $leaf $natId)$(if ($natGateways.Contains($natId)) { " ($(@(@(& $at $natGateways[$natId] 'publicIpAddresses') + @(& $at $natGateways[$natId] 'publicIpPrefixes') | Where-Object { $_ }).Count) public IP(s)/prefix(es))" })" } else { '' })
                    Outbound                = $outbound
                    DefaultOutboundAccess   = $(if ($false -eq $defaultOutbound) { 'Off (private subnet)' } elseif ($true -eq $defaultOutbound) { 'On' } else { 'On (default)' })
                    ServiceEndpoints        = @(@(& $at $sp 'serviceEndpoints') | Where-Object { $_ } | ForEach-Object { [string](& $at $_ 'service') }) -join ', '
                    ServiceEndpointPolicies = @(@(& $at $sp 'serviceEndpointPolicies') | Where-Object { $_ } | ForEach-Object { & $leaf (& $at $_ 'id') }) -join ', '
                    Delegations             = $delegations -join ', '
                    PrivateEndpoints        = $peCount
                    PrivateEndpointPolicies = [string](& $at $sp 'privateEndpointNetworkPolicies')
                    PrivateLinkPolicies     = [string](& $at $sp 'privateLinkServiceNetworkPolicies')
                    Nics                    = $computeNics.Count
                    Vms                     = $vms.Count
                    PublicIpNics            = $withPublicIp.Count
                    IpForwardingNics        = @($computeNics | Where-Object Forwarding).Count
                    FlowLogs                = $subnetFlow
                    SubscriptionName        = & $subscriptionOf $vnetId
                    ResourceGroup           = [string]$vnet['resourceGroup']
                    SubnetId                = [string]$subnet['id']
                })
            $vnetSubnets.Add($row)
            $subnets.Add($row)

            # --- Subnet findings ---------------------------------------------------------------------------------
            if ($usable -and $row.UsedPercent -ge 80) {
                & $finding $(if ($row.Available -eq 0) { 'High' } elseif ($row.UsedPercent -ge 95) { 'High' } else { 'Medium' }) 'Capacity' $(if ($row.Available -eq 0) { 'Subnet full' } else { 'Subnet nearly full' }) $name $subnetName "$used of $usable usable IPs in $($row.Prefix) are in use ($($row.UsedPercent)%), $($row.Available) left. Scale-outs, new VMs and private endpoints fail when it is full." 'Add an address range to the subnet (if free space is left in the VNet), or move workloads to a larger subnet.' $row.SubnetId
            }
            if ($usable -ge 1019 -and $usable -and $row.UsedPercent -lt 2 -and -not $purpose -and -not $delegations.Count) {
                & $finding 'Low' 'Capacity' 'Oversized subnet' $name $subnetName "$($row.Prefix) offers $usable IPs; $used are in use." 'Size subnets for expected growth: an empty, large subnet holds address space other subnets (and peered networks) may need. It can be resized while nothing is in it.' $row.SubnetId
            }
            if ($sizing.Contains($subnetName.ToLowerInvariant())) {
                $needed = $sizing[$subnetName.ToLowerInvariant()]
                $smallest = @($ranges | Sort-Object Length -Descending | Select-AACFirst 1)
                if ($smallest.Count -and $smallest[0].Length -gt $needed) {
                    & $finding $(if ($subnetName -ieq 'GatewaySubnet') { 'Medium' } else { 'High' }) 'Connectivity' "$subnetName is smaller than /$needed" $name $subnetName "$($row.Prefix) is a /$($smallest[0].Length); $purpose needs /$needed or larger$(if ($subnetName -ieq 'GatewaySubnet') { ' (recommended: coexisting VPN and ExpressRoute gateways, more connections)' })." "Resize $subnetName to /$needed or larger." $row.SubnetId
                }
            }
            if ($subnetName -ieq 'GatewaySubnet' -and $nsgId) {
                & $finding 'High' 'Connectivity' 'NSG on GatewaySubnet' $name $subnetName "NSG $(& $leaf $nsgId) is associated with the GatewaySubnet, which isn't supported: the VPN or ExpressRoute gateway may stop working." 'Remove the NSG from GatewaySubnet.' $row.SubnetId
            }
            if ($subnetName -ieq 'GatewaySubnet' -and $defaultRoute) {
                & $finding 'High' 'Connectivity' 'Default route on GatewaySubnet' $name $subnetName "Route table $(& $leaf $routeTableId) sends 0.0.0.0/0 to $defaultHop from the GatewaySubnet, which isn't supported." 'Remove the 0.0.0.0/0 route from the GatewaySubnet route table.' $row.SubnetId
            }
            if (-not $nsgId -and -not $purpose -and ($computeNics.Count -or $peCount)) {
                & $finding 'Medium' 'Security' 'Subnet without an NSG' $name $subnetName "$($computeNics.Count) NIC(s) and $peCount private endpoint(s) in it, with no network security group: all traffic the platform allows reaches them." 'Associate an NSG with the subnet (deny by default, allow what the workload needs).' $row.SubnetId
            }
            elseif (-not $nsgId -and -not $purpose -and -not $delegations.Count) {
                & $finding 'Low' 'Security' 'Subnet without an NSG' $name $subnetName 'Nothing is in it yet, but whatever is deployed there will have no network security group.' 'Associate an NSG before workloads are added (Azure Policy can require it).' $row.SubnetId
            }
            if ($withPublicIp.Count) {
                & $finding 'Medium' 'Security' 'VMs reachable on public IPs' $name $subnetName "$($withPublicIp.Count) NIC(s) have their own public IP: $(@($withPublicIp | Select-AACFirst 8 | ForEach-Object { [string]$_.Nic['name'] }) -join ', ')." 'Remove the public IPs: reach VMs through Azure Bastion or a VPN, and publish apps through a load balancer, Application Gateway or Front Door.' $row.SubnetId
            }
            if ($outbound -eq 'Default outbound access') {
                & $finding 'Medium' 'Security' 'Relies on default outbound access' $name $subnetName "$($computeNics.Count) NIC(s) reach the internet through Azure's implicit default outbound access - no NAT gateway, no route to a firewall, no public IP. It is being retired (new virtual networks get private subnets by default), its IP isn't yours and can change." 'Give the subnet an explicit outbound path - a NAT gateway, or a 0.0.0.0/0 route to Azure Firewall - and set it private (defaultOutboundAccess = false). Unless BGP routes from a hub (Virtual WAN, an NVA) already send it there.' $row.SubnetId
            }
            if ($peCount -and [string](& $at $sp 'privateEndpointNetworkPolicies') -in '', 'Disabled') {
                & $finding 'Low' 'Security' 'Private endpoint network policies off' $name $subnetName "$peCount private endpoint(s) in it, but NSGs and route tables don't apply to them (privateEndpointNetworkPolicies is Disabled)." 'Set privateEndpointNetworkPolicies to Enabled so NSG rules and user-defined routes apply to the private endpoints too.' $row.SubnetId
            }
            if ($row.IpForwardingNics -and -not @($RouteTable | Where-Object { @(& $at $_ 'routes') | Where-Object { $_ -and [string](& $at $_ 'properties', 'nextHopType') -eq 'VirtualAppliance' } }).Count) {
                & $finding 'Low' 'Connectivity' 'IP forwarding with no route to it' $name $subnetName "$($row.IpForwardingNics) NIC(s) forward IP traffic (a network virtual appliance), but no route table in scope sends traffic to a virtual appliance." 'Check the NVA is still needed; if so, route traffic to it with a route table.' $row.SubnetId
            }
        }

        # --- Address space and free ranges --------------------------------------------------------------------------
        $freeBlocks = @(ConvertTo-AACCidrRange -Space $space -Used $usedPrefixes.ToArray() | Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, Start)
        foreach ($block in $freeBlocks) { $free.Add((& $object 'AAC.VirtualNetworkFreeRange' ([ordered]@{ VirtualNetwork = $name; AddressSpace = $block.Space; Prefix = $block.Prefix; Size = $block.Size; ResourceId = [string]$vnet['id'] }))) }
        $inSubnets = & $sumOf @($usedPrefixes | ForEach-Object { ConvertTo-AACCidrRange $_ } | Where-Object { $_.Version -eq 4 -and $_.Valid }) 'Size'
        $usableAll = & $sumOf $vnetSubnets 'Usable'
        $usedAll = & $sumOf $vnetSubnets 'Used'

        # Overlapping address spaces with any other VNet the account can see.
        $overlaps = @(foreach ($other in $AllNetwork) {
                $otherId = & $lower $other['id']
                if ($otherId -eq $vnetId) { continue }
                $clash = @(foreach ($mine in $spaceRanges | Where-Object { $_.Version -eq 4 -and $_.Valid }) {
                        foreach ($theirs in @($other['prefixes']) | Where-Object { $_ } | ForEach-Object { ConvertTo-AACCidrRange $_ } | Where-Object { $_.Version -eq 4 -and $_.Valid }) {
                            if ($mine.Start -le $theirs.End -and $theirs.Start -le $mine.End) { "$($mine.Prefix) / $($theirs.Prefix)" }
                        }
                    })
                if ($clash.Count) { @{ Name = [string]$other['name']; Id = $otherId; Clash = $clash -join ', '; Subscription = & $subscriptionOf $otherId } }
            })

        # --- Peerings ----------------------------------------------------------------------------------------------
        $vnetPeerings = [System.Collections.Generic.List[object]]::new()
        foreach ($peering in @(& $at $properties 'virtualNetworkPeerings' | Where-Object { $_ })) {
            $pp = & $at $peering 'properties'
            $remoteId = & $lower (& $at $pp 'remoteVirtualNetwork', 'id')
            $remote = $allNetworks[$remoteId]
            $remoteSpace = @(& $list (& $at $pp 'remoteAddressSpace', 'addressPrefixes'))
            $state = [string](& $at $pp 'peeringState')
            $sync = [string](& $at $pp 'peeringSyncLevel')
            $remoteLocation = if ($remote) { [string]$remote['location'] } else { '' }
            $reverse = if ($remote) { @($remote['peers'] | Where-Object { (& $lower $_) -eq $vnetId }).Count -gt 0 } else { $null }
            $isHub = $remoteId -match '/virtualhubs/' -or (& $leaf $remoteId) -like 'HV_*'
            $row = & $object 'AAC.VirtualNetworkPeering' ([ordered]@{
                    VirtualNetwork         = $name
                    Peering                = [string]$peering['name']
                    RemoteVirtualNetwork   = $(if ($remote) { [string]$remote['name'] } else { & $leaf $remoteId })
                    RemoteSubscription     = & $subscriptionOf $remoteId
                    RemoteLocation         = $remoteLocation
                    State                  = $state
                    Sync                   = $sync
                    Global                 = [bool]($remoteLocation -and $remoteLocation -ne [string]$vnet['location'])
                    AllowVirtualNetworkAccess = [bool](& $at $pp 'allowVirtualNetworkAccess')
                    AllowForwardedTraffic  = [bool](& $at $pp 'allowForwardedTraffic')
                    AllowGatewayTransit    = [bool](& $at $pp 'allowGatewayTransit')
                    UseRemoteGateways      = [bool](& $at $pp 'useRemoteGateways')
                    RemoteAddressSpace     = $remoteSpace -join ', '
                    SubnetPeering          = $(if ($false -eq (& $at $pp 'peerCompleteVnets')) { "local $(@(& $at $pp 'localSubnetNames') -join ', ') <-> remote $(@(& $at $pp 'remoteSubnetNames') -join ', ')" } else { '' })
                    RemoteVisible          = [bool]$remote
                    ReversePeering         = $reverse
                    VirtualWanHub          = $isHub
                    RemoteVirtualNetworkId = $remoteId
                    VirtualNetworkId       = [string]$vnet['id']
                })
            $vnetPeerings.Add($row)
            $peerings.Add($row)
            $remoteName = $row.RemoteVirtualNetwork
            if ($state -and $state -ne 'Connected') {
                & $finding 'High' 'Connectivity' "Peering $state" $name $row.Peering "The peering to $remoteName is $state$(if ($state -eq 'Initiated') { ': the remote network has no peering back' }) - no traffic flows between the two networks." $(if ($state -eq 'Initiated') { "Create the peering from $remoteName back to $name." } else { 'Delete and recreate the peering on both sides (the remote side was deleted or changed).' }) $vnetId
            }
            if ($sync -and $sync -ne 'FullyInSync') {
                & $finding 'Medium' 'Connectivity' 'Peering out of sync' $name $row.Peering "The peering to $remoteName is $($sync): an address space changed and the peering wasn't synced - the new ranges aren't reachable across it." 'Sync the peering (Sync in the portal, or az network vnet peering sync) on the side that is out of sync.' $vnetId
            }
            if ($row.UseRemoteGateways -and -not $row.AllowForwardedTraffic) {
                & $finding 'Low' 'Connectivity' 'Gateway transit without forwarded traffic' $name $row.Peering "The peering uses $remoteName's gateway, but doesn't allow forwarded traffic - traffic an NVA or firewall in the hub forwards is dropped." 'Allow forwarded traffic on the peering if the hub routes traffic through a firewall or NVA.' $vnetId
            }
            if ($row.Global) {
                & $finding 'Info' 'Cost' 'Global peering' $name $row.Peering "$name ($([string]$vnet['location'])) peers with $remoteName ($remoteLocation): inbound and outbound data across regions is charged per GB." 'Expected for multi-region designs; check the data volume in Cost Management.' $vnetId
            }
            if (-not $row.RemoteVisible -and -not $isHub) {
                & $finding 'Info' 'Connectivity' 'Remote network not visible' $name $row.Peering "$remoteName is in a subscription or tenant this account can't read: its state and address space can't be checked from here." 'Check it from an account that can read the remote subscription.' $vnetId
            }
        }

        # --- VNet findings ------------------------------------------------------------------------------------------
        # The public IPs in this network: on NICs, gateways, firewalls and Bastion hosts.
        $publicIds = @(@($vnetSubnets | ForEach-Object { $nicsBySubnet[$_.SubnetId.ToLowerInvariant()] } | Where-Object { $_ -and $_.PublicIp -and -not $_.PrivateEndpoint } | ForEach-Object { $_.PublicIp }) +
            @(@($gateways) + @($firewalls) + @($bastions) | Where-Object { $_ } | ForEach-Object { @(& $at $_ 'ipConfigurations') } | Where-Object { $_ } | ForEach-Object { & $lower (& $at $_ 'properties', 'publicIPAddress', 'id') }) |
            Where-Object { $_ } | Select-Object -Unique)
        $vnetPublicIps = [Math]::Max($publicIds.Count, $publicIpCount)
        $ipProtected = @($publicIds | Where-Object { $publicIps.Contains($_) -and [string](& $at $publicIps[$_] 'protectionMode') -eq 'Enabled' }).Count
        $computeAll = [int](& $sumOf $vnetSubnets 'Nics')
        $peAll = [int](& $sumOf $vnetSubnets 'PrivateEndpoints')
        if (-not $vnetSubnets.Count) {
            & $finding 'Low' 'Operations' 'Virtual network with no subnets' $name '' 'It has an address space but no subnet - nothing can be deployed in it.' 'Add subnets, or delete the virtual network if it is no longer used.' $vnetId
        }
        elseif (-not $usedAll -and -not $vnetPeerings.Count) {
            & $finding 'Low' 'Operations' 'Unused virtual network' $name '' 'No IP configuration in any subnet and no peering.' 'Delete it if nothing is planned for it: it holds address space.' $vnetId
        }
        if ($total -and -not $freeBlocks.Count) {
            & $finding 'Low' 'Capacity' 'No free address space' $name '' "Subnets cover all of $($space -join ', '): no subnet can be added." 'Add an address range to the virtual network (peerings then need a sync).' $vnetId
        }
        foreach ($overlap in $overlaps | Select-AACFirst 10) {
            $peered = @($vnetPeerings | Where-Object { $_.RemoteVirtualNetworkId -eq $overlap.Id }).Count
            if (-not $peered) { & $finding 'Low' 'Connectivity' 'Overlapping address space' $name $overlap.Name "$($overlap.Clash) overlap with $($overlap.Name) ($($overlap.Subscription)): the two networks can't be peered or routed to each other." 'Plan non-overlapping ranges (an IPAM or IP plan); re-address one of them if they ever need to connect.' $vnetId }
        }
        if ($vnetPublicIps -and -not $ddosOn) {
            & $finding 'Medium' 'Security' 'No DDoS Network Protection' $name '' "$vnetPublicIps public IP(s) in the network are covered by DDoS infrastructure protection only$(if ($ipProtected) { " ($ipProtected with DDoS IP Protection)" })." 'Enable Azure DDoS Network Protection on the virtual network (a plan can cover many networks), or DDoS IP Protection on each public IP.' $vnetId
        }
        if (($computeAll -or $peAll) -and -not $vnetFlowLog -and -not @($vnetSubnets | Where-Object { $_.FlowLogs -in 'Subnet flow log', 'VNet flow log' }).Count) {
            & $finding 'Medium' 'Operations' 'No virtual network flow logs' $name '' "Traffic in the network isn't logged$(if (@($vnetSubnets | Where-Object FlowLogs -EQ 'NSG flow log').Count) { ' except by NSG flow logs, which retire on 30 September 2027' })." 'Enable virtual network flow logs (Network Watcher) with Traffic Analytics.' $vnetId
        }
        if ($computeAll -and -not ($encryption -and [bool](& $at $encryption 'enabled'))) {
            & $finding 'Low' 'Security' 'Virtual network encryption off' $name '' 'Traffic between VMs in the network (and across peerings) isn''t encrypted by the network.' 'Enable virtual network encryption (supported VM sizes encrypt traffic between them with DTLS).' $vnetId
        }
        if ($dns.Count -eq 1) {
            & $finding 'Low' 'Resilience' 'Single custom DNS server' $name '' "Every VM resolves names through $($dns[0]) alone: when it is down, name resolution fails." 'Configure at least two DNS servers (or Azure DNS Private Resolver).' $vnetId
        }
        if ($peAll -and -not $dns.Count) {
            $endpointsHere = @($PrivateEndpoint | Where-Object { (& $vnetOf (& $at $_ 'subnet')) -eq $vnetId })
            $unlinked = @(foreach ($endpoint in $endpointsHere) {
                    foreach ($group in @($endpoint['groupIds'])) { $zone = $privateZones[([string]$group).ToLowerInvariant()]; if ($zone -and $zoneNames -notcontains $zone) { "$([string]$endpoint['name']) ($($group): $zone)" } }
                })
            if ($unlinked.Count) {
                & $finding 'Medium' 'Connectivity' 'Private endpoints without their private DNS zone' $name '' "The network uses Azure DNS, but isn't linked to the private DNS zone of $($unlinked.Count) private endpoint(s): $(@($unlinked | Select-AACFirst 6) -join '; ')$(if ($unlinked.Count -gt 6) { '; ...' }). Their names resolve to public IPs." 'Link the privatelink zones to the virtual network (or to the hub that resolves for it), with a DNS zone group on each private endpoint.' $vnetId
            }
        }
        if ($computeAll -and -not $bastions.Count -and -not @($vnetPeerings | Where-Object { $_.UseRemoteGateways -or $_.AllowForwardedTraffic }).Count -and @($vnetSubnets | Where-Object PublicIpNics).Count) {
            & $finding 'Info' 'Security' 'No Azure Bastion' $name '' 'VMs here are reached on public IPs, and there is no Azure Bastion in this network.' 'Use Azure Bastion (here or in a peered hub) to reach VMs without public IPs.' $vnetId
        }
        foreach ($gw in $gateways) {
            $sku = [string](& $at $gw 'sku')
            if ($sku -eq 'Basic') { & $finding 'Medium' 'Resilience' 'Basic VPN gateway' $name ([string]$gw['name']) 'The Basic SKU has no zone redundancy, no BGP, limited tunnels and throughput, and no ExpressRoute coexistence.' 'Move to a VpnGw1AZ (or larger AZ) SKU.' ([string]$gw['id']) }
            elseif ($sku -and $sku -notmatch 'AZ$' -and $sku -ne 'Standard' -and $sku -notmatch '^ErGw') { & $finding 'Low' 'Resilience' 'Gateway not zone-redundant' $name ([string]$gw['name']) "$sku is not a zone-redundant SKU: a zone outage takes the gateway down." "Move to the AZ SKU ($($sku)AZ) where the region has zones." ([string]$gw['id']) }
        }

        $role = if ($gateways.Count -or $firewalls.Count -or @($vnetPeerings | Where-Object AllowGatewayTransit).Count) { 'Hub' } elseif (@($vnetPeerings | Where-Object { $_.UseRemoteGateways -or $_.VirtualWanHub }).Count) { 'Spoke' } elseif ($vnetPeerings.Count) { 'Peered' } else { 'Standalone' }
        $vnets.Add((& $object 'AAC.VirtualNetwork' ([ordered]@{
                        Name                = $name
                        Role                = $role
                        Location            = [string]$vnet['location']
                        ResourceGroup       = [string]$vnet['resourceGroup']
                        SubscriptionName    = & $subscriptionOf $vnetId
                        AddressSpace        = $space -join ', '
                        TotalIps            = $total
                        IpsInSubnets        = $inSubnets
                        UnallocatedIps      = [Math]::Max(0, $total - $inSubnets)
                        UsableIps           = $usableAll
                        UsedIps             = $usedAll
                        AvailableIps        = [Math]::Max(0, $usableAll - $usedAll)
                        UsedPercent         = $(if ($usableAll) { [Math]::Round($usedAll / $usableAll * 100, 1) } else { $null })
                        SubnetCount         = $vnetSubnets.Count
                        FreeRanges          = @($freeBlocks | Select-AACFirst 6 | ForEach-Object { $_.Prefix }) -join ', '
                        PeeringCount        = $vnetPeerings.Count
                        PeeringsNotConnected = @($vnetPeerings | Where-Object { $_.State -ne 'Connected' }).Count
                        DnsServers          = $(if ($dns.Count) { $dns -join ', ' } else { 'Azure-provided' })
                        PrivateDnsZones     = @($zoneNames | Sort-Object) -join ', '
                        DnsResolvers        = @($resolvers | ForEach-Object { [string]$_['name'] }) -join ', '
                        DdosProtection      = $(if ($ddosOn) { "Network Protection ($(& $leaf $planId))" } elseif ($ipProtected) { "IP Protection on $ipProtected IP(s)" } else { 'Infrastructure only' })
                        Encryption          = $(if ($encryption -and [bool](& $at $encryption 'enabled')) { "On ($(& $at $encryption 'enforcement'))" } else { 'Off' })
                        FlowLogs            = $(if ($vnetFlowLog) { "VNet flow log$(if ([bool]$vnetFlowLog['analytics']) { ', Traffic Analytics' })" } else { 'None' })
                        Gateways            = @($gateways | ForEach-Object { "$([string]$_['name']) ($([string](& $at $_ 'gatewayType')) $([string](& $at $_ 'sku')))" }) -join ', '
                        Firewalls           = @($firewalls | ForEach-Object { "$([string]$_['name']) ($([string](& $at $_ 'tier')))" }) -join ', '
                        Bastions            = @($bastions | ForEach-Object { "$([string]$_['name']) ($([string](& $at $_ 'sku')))" }) -join ', '
                        Nics                = $computeAll
                        PrivateEndpoints    = $peAll
                        PublicIps           = $vnetPublicIps
                        Overlaps            = @($overlaps | ForEach-Object { $_.Name }) -join ', '
                        FlowTimeoutMinutes  = & $at $properties 'flowTimeoutInMinutes'
                        BgpCommunity        = [string](& $at $properties 'bgpCommunities', 'virtualNetworkCommunity')
                        Tags                = $(if ($vnet['tags'] -is [System.Collections.IDictionary] -and $vnet['tags'].Count) { @($vnet['tags'].Keys | Sort-Object | ForEach-Object { "$_=$($vnet['tags'][$_])" }) -join '; ' } else { '' })
                        ProvisioningState   = [string](& $at $properties 'provisioningState')
                        ResourceId          = [string]$vnet['id']
                        High = 0; Medium = 0; Low = 0
                    })))

        # Private endpoints, for the report.
        foreach ($endpoint in @($PrivateEndpoint | Where-Object { (& $vnetOf (& $at $_ 'subnet')) -eq $vnetId })) {
            $groups = @($endpoint['groupIds'] | Where-Object { $_ })
            $zones = @($groups | ForEach-Object { $privateZones[([string]$_).ToLowerInvariant()] } | Where-Object { $_ })
            $endpoints.Add((& $object 'AAC.VirtualNetworkPrivateEndpoint' ([ordered]@{
                            VirtualNetwork = $name; Subnet = & $leaf (& $at $endpoint 'subnet'); PrivateEndpoint = [string]$endpoint['name']; Target = & $leaf $endpoint['target']; TargetType = $(if ([string]$endpoint['target'] -match '/providers/([^/]+/[^/]+)/') { $Matches[1] } else { '' })
                            Groups = $groups -join ', '; Status = [string]$endpoint['status']; ZoneLinked = $(if ($dns.Count) { 'Custom DNS' } elseif (-not $zones.Count) { '' } elseif (@($zones | Where-Object { $zoneNames -contains $_ }).Count -eq $zones.Count) { 'Yes' } else { 'No' })
                            ResourceId = [string]$endpoint['id']; VirtualNetworkId = [string]$vnet['id']
                        })))
            if ([string]$endpoint['status'] -and [string]$endpoint['status'] -ne 'Approved') {
                & $finding 'Medium' 'Connectivity' "Private endpoint $([string]$endpoint['status'])" $name ([string]$endpoint['name']) "The connection to $(& $leaf $endpoint['target']) is $([string]$endpoint['status']): no traffic flows through the private endpoint." 'Approve the connection on the target resource (or remove the endpoint).' ([string]$endpoint['id'])
            }
        }
    }

    # --- NSGs: the NSG assessment's findings, on the networks they apply to -------------------------------------------
    if ($NsgAssessment) {
        foreach ($item in @($NsgAssessment.Findings)) {
            $nsg = ([string]$item.Nsg)
            $where = @($subnets | Where-Object { $_.Nsg -eq $nsg } | ForEach-Object { $_.VirtualNetwork } | Select-Object -Unique)
            $severity = if ([string]$item.Severity -in 'High', 'Medium', 'Low') { [string]$item.Severity } else { 'Info' }
            & $finding $severity 'Security' "NSG: $($item.Check)" ($where -join ', ') "$nsg$(if ($item.Rule) { " / $($item.Rule)" })" ([string]$item.Detail) ([string]$item.Recommendation) ([string]$item.NsgId) 'NSG'
        }
    }

    # --- ASGs: who is in them, which rules name them ----------------------------------------------------------------
    $asgRules = @{}
    foreach ($nsg in $NetworkSecurityGroup) {
        foreach ($rule in @(& $at $nsg 'properties', 'securityRules' | Where-Object { $_ })) {
            foreach ($side in 'sourceApplicationSecurityGroups', 'destinationApplicationSecurityGroups') {
                foreach ($asg in @(& $at $rule 'properties', $side | Where-Object { $_ })) {
                    $id = & $lower (& $at $asg 'id')
                    if (-not $asgRules.Contains($id)) { $asgRules[$id] = [System.Collections.Generic.List[string]]::new() }
                    $asgRules[$id].Add("$([string]$nsg['name'])/$([string]$rule['name']) ($(if ($side -like 'source*') { 'source' } else { 'destination' }))")
                }
            }
        }
    }
    $asgs = @(foreach ($asg in $ApplicationSecurityGroup) {
            $id = & $lower $asg['id']
            $members = @(if ($asgUse.Contains($id)) { $asgUse[$id] })
            $rules = @(if ($asgRules.Contains($id)) { $asgRules[$id] })
            $networks = @($members | ForEach-Object { & $leaf $_.VirtualNetwork } | Select-Object -Unique)
            if (-not $members.Count -and -not $rules.Count -and -not @($networks | Where-Object { $_ }).Count) {
                & $finding 'Low' 'Operations' 'Unused application security group' '' ([string]$asg['name']) 'No NIC is in it and no NSG rule names it.' 'Delete it if it is no longer needed.' ([string]$asg['id'])
            }
            elseif ($rules.Count -and -not $members.Count) {
                & $finding 'Low' 'Security' 'NSG rules name an empty application security group' '' ([string]$asg['name']) "$($rules.Count) rule(s) use it - $(@($rules | Select-AACFirst 4) -join ', ') - but no NIC is in it, so they match nothing." 'Add the intended NICs to the ASG, or remove the rules.' ([string]$asg['id'])
            }
            & $object 'AAC.ApplicationSecurityGroupUse' ([ordered]@{
                    Asg = [string]$asg['name']; ResourceGroup = [string]$asg['resourceGroup']; Location = [string]$asg['location']; SubscriptionName = & $subscriptionOf $id
                    Nics = $members.Count; Members = @($members | ForEach-Object { if ($_.Vm) { "$($_.Nic) ($($_.Vm))" } else { $_.Nic } } | Select-Object -Unique) -join ', '
                    VirtualNetworks = $networks -join ', '; Rules = $rules.Count; RuleNames = $rules -join ', '; ResourceId = [string]$asg['id']
                })
        })

    # --- Severity counts, order ---------------------------------------------------------------------------------------
    $rank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $rank[$_.Severity] } }, Category, VirtualNetwork, Finding)
    foreach ($row in $vnets) {
        # Its own findings by resource ID (names repeat across subscriptions);
        # gateways, private endpoints and NSGs by the network's name.
        $prefix = "$($row.ResourceId.ToLowerInvariant())/"
        $mine = @($sorted | Where-Object { ($_.ResourceId.ToLowerInvariant() + '/').StartsWith($prefix) -or (@(([string]$_.VirtualNetwork) -split ',\s*') -contains $row.Name -and -not $_.ResourceId.ToLowerInvariant().Contains('/microsoft.network/virtualnetworks/')) })
        $row.High = @($mine | Where-Object Severity -EQ 'High').Count
        $row.Medium = @($mine | Where-Object Severity -EQ 'Medium').Count
        $row.Low = @($mine | Where-Object Severity -EQ 'Low').Count
        $id = $row.ResourceId
        $row | Add-Member -NotePropertyMembers ([ordered]@{
                Subnets          = @($subnets | Where-Object { $_.SubnetId.ToLowerInvariant().StartsWith("$($id.ToLowerInvariant())/") })
                Peerings         = @($peerings | Where-Object { $_.VirtualNetworkId -eq $id })
                FreeRangeList    = @($free | Where-Object { $_.ResourceId -eq $id })
                PrivateEndpointList = @($endpoints | Where-Object { $_.VirtualNetworkId -eq $id })
                Findings         = $mine
            })
    }
    $sum = $sumOf
    $stats = [ordered]@{
        VirtualNetworks    = $vnets.Count
        Subnets            = $subnets.Count
        TotalIps           = & $sum $vnets 'TotalIps'
        UsableIps          = & $sum $vnets 'UsableIps'
        UsedIps            = & $sum $vnets 'UsedIps'
        AvailableIps       = & $sum $vnets 'AvailableIps'
        UnallocatedIps     = & $sum $vnets 'UnallocatedIps'
        UsedPercent        = $(if ((& $sum $vnets 'UsableIps')) { [Math]::Round((& $sum $vnets 'UsedIps') / (& $sum $vnets 'UsableIps') * 100, 1) } else { $null })
        FullSubnets        = @($subnets | Where-Object { $null -ne $_.UsedPercent -and $_.UsedPercent -ge 80 }).Count
        Peerings           = $peerings.Count
        PeeringProblems    = @($peerings | Where-Object { $_.State -ne 'Connected' -or ($_.Sync -and $_.Sync -ne 'FullyInSync') }).Count
        SubnetsWithoutNsg  = @($subnets | Where-Object { -not $_.Nsg -and $_.Purpose -notin 'Gateway', 'Azure Firewall', 'Azure Firewall management', 'Route Server' }).Count
        PrivateEndpoints   = $endpoints.Count
        Asgs               = $asgs.Count
        High               = @($sorted | Where-Object Severity -EQ 'High').Count
        Medium             = @($sorted | Where-Object Severity -EQ 'Medium').Count
        Low                = @($sorted | Where-Object Severity -EQ 'Low').Count
        Info               = @($sorted | Where-Object Severity -EQ 'Info').Count
    }
    @{
        VirtualNetworks  = @($vnets | Sort-Object -Property @{ Expression = { $_.High }; Descending = $true }, @{ Expression = { $_.Medium }; Descending = $true }, Name)
        Subnets          = $subnets.ToArray()
        Peerings         = $peerings.ToArray()
        FreeRanges       = $free.ToArray()
        Asgs             = $asgs
        PrivateEndpoints = $endpoints.ToArray()
        Findings         = $sorted
        Nsg              = $NsgAssessment
        Stats            = $stats
    }
}
