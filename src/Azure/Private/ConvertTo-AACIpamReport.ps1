function ConvertTo-AACIpamReport {
    <#
    .SYNOPSIS
        Measures Azure's address space against an address plan: spaces and
        blocks, the networks in them, every subnet and private IP address,
        overlaps, free space and the next ranges to hand out - with findings.
    .DESCRIPTION
        -Plan comes from Read-AACIpamPlan. The rest are Azure Resource Graph
        rows: virtual networks (with their subnets, peerings and DNS
        servers), Virtual WAN hubs, network interfaces, scale set network
        interfaces, other resources that take addresses from a subnet (load
        balancers, firewalls, Bastion, gateways, application gateways,
        Private Link services), private endpoints and public IPs.

        A subnet's used addresses are what Azure lists in it
        (ipConfigurations, and application gateway configurations): every
        one is an IpAddresses row, so the count and the list always agree -
        an unattached network interface included. Azure keeps 5 addresses
        of every subnet (the first four and the last), so usable = size - 5.

        Returns @{ Spaces; Blocks; Networks; Subnets; IpAddresses; Overlaps;
        FreeRanges; NextAvailable; CidrChecks; Findings; Tree; Stats }:
          Blocks        each block's networks, address space allocated (the
                        union of the network prefixes in it, external ranges
                        included), free space, largest free range, how many
                        of the first -NextAvailable size still fit, status
                        against -WarningPercent and -CriticalPercent
          Networks      Managed (every IPv4 prefix in a block), Partly
                        managed, or Unmanaged; External ranges too
          Overlaps      every pair of networks (and external ranges) whose
                        address spaces overlap - High when they are peered
                        (traffic can't route), Medium with an external range
                        or a hub, Low otherwise (they can never be peered)
          NextAvailable per block and size: the best fit (the smallest free
                        range it fits, so big ranges stay whole) and the
                        lowest free address
          CidrChecks    each -TestCidr: free, taken or partly taken, and by
                        what
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Plan,

        [AllowEmptyCollection()]
        [object[]] $VirtualNetwork = @(),

        [AllowEmptyCollection()]
        [object[]] $Hub = @(),

        [AllowEmptyCollection()]
        [object[]] $NetworkInterface = @(),

        [AllowEmptyCollection()]
        [object[]] $ScaleSetInterface = @(),

        [AllowEmptyCollection()]
        [object[]] $IpResource = @(),

        [AllowEmptyCollection()]
        [object[]] $PrivateEndpoint = @(),

        [AllowEmptyCollection()]
        [object[]] $PublicIp = @(),

        [hashtable] $SubscriptionName = @{},

        [int[]] $NextAvailable = @(24),

        [AllowEmptyCollection()]
        [string[]] $TestCidr = @(),

        [int] $WarningPercent = 80,

        [int] $CriticalPercent = 90
    )

    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary]) { $Value = $Value[$key] } else { return $null } }
        $Value
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    $parseCache = @{}
    $parse = { param([string] $Prefix) if (-not $parseCache.ContainsKey($Prefix)) { $parseCache[$Prefix] = ConvertTo-AACCidrRange -Prefix $Prefix }; $parseCache[$Prefix] }
    $toIp = { param([long] $Value) '{0}.{1}.{2}.{3}' -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255) }
    $ipValue = { param([string] $Ip) if ($Ip -match '^(\d+)\.(\d+)\.(\d+)\.(\d+)$') { ([long]$Matches[1] -shl 24) + ([long]$Matches[2] -shl 16) + ([long]$Matches[3] -shl 8) + [long]$Matches[4] } else { [long]::MaxValue } }
    $rangeText = { param([long] $Start, [long] $End) "$(& $toIp $Start) - $(& $toIp $End)" }
    $percent = { param($Part, $Whole) if ($Whole) { [Math]::Round(100.0 * $Part / $Whole, 1) } else { $null } }
    $subName = { param([string] $Id) $k = & $lower $Id; if ($SubscriptionName.ContainsKey($k)) { $SubscriptionName[$k] } else { [string]$Id } }
    # The size of a set of ranges, overlaps counted once.
    $unionSize = {
        param([object[]] $Ranges)
        $total = [long]0; $cursor = [long]-1
        foreach ($r in @($Ranges | Where-Object { $_ } | Sort-Object -Property { $_.Start })) {
            $from = [Math]::Max([long]$r.Start, $cursor + 1)
            if ($r.End -ge $from) { $total += $r.End - $from + 1; $cursor = [long]$r.End }
        }
        $total
    }
    $status = {
        param($Used, [bool] $Full)
        if ($Full) { 'Full' } elseif ($null -eq $Used) { 'Empty' } elseif ($Used -ge $CriticalPercent) { 'Critical' } elseif ($Used -ge $WarningPercent) { 'Warning' } else { 'OK' }
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $find = {
        param([string] $Severity, [string] $Category, [string] $Space, [string] $Item, [string] $Title, [string] $Detail, [string] $Fix, [string] $ResourceId = '')
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.IpamFinding'; Severity = $Severity; Category = $Category; Space = $Space; Item = $Item; Finding = $Title; Detail = $Detail; Recommendation = $Fix; ResourceId = $ResourceId })
    }

    # --- The blocks a range sits in -----------------------------------------------------------------------------------
    $blocks = @($Plan.Blocks)
    $containing = { param($Range) @($blocks | Where-Object { $_.Start -le $Range.Start -and $Range.End -le $_.End }) }
    $touching = { param($Range) @($blocks | Where-Object { $_.Start -le $Range.End -and $Range.Start -le $_.End }) }

    # --- Every address a resource takes from a subnet, by its IP configuration ID -----------------------------------
    $publicIps = @{}
    foreach ($p in $PublicIp) { if ($p) { $publicIps[(& $lower $p['id'])] = [string]$p['ipAddress'] } }
    $endpointTargets = @{}
    foreach ($pe in $PrivateEndpoint) { if ($pe) { $endpointTargets[(& $lower $pe['id'])] = @{ Name = [string]$pe['name']; Target = ([string]$pe['target'] -split '/')[-1] } } }
    $configs = @{}
    $addConfig = {
        param($Config, [hashtable] $Owner)
        $id = & $lower $Config['id']
        if (-not $id) { return }
        $publicId = & $lower (& $at $Config 'properties', 'publicIPAddress', 'id')
        $configs[$id] = $Owner + @{
            Ip = [string](& $at $Config 'properties', 'privateIPAddress')
            Allocation = [string](& $at $Config 'properties', 'privateIPAllocationMethod')
            PublicIp = $(if ($publicId -and $publicIps.ContainsKey($publicId)) { $publicIps[$publicId] } else { '' })
        }
    }
    foreach ($nic in $NetworkInterface) {
        if (-not $nic) { continue }
        $vm = [string]$nic['vm']; $pe = & $lower $nic['privateEndpoint']
        $owner = if ($vm) { @{ Kind = 'Virtual machine'; Attached = ($vm -split '/')[-1] } }
        elseif ($pe) { @{ Kind = 'Private endpoint'; Attached = $(if ($endpointTargets.ContainsKey($pe)) { "$($endpointTargets[$pe].Name) -> $($endpointTargets[$pe].Target)" } else { ($pe -split '/')[-1] }) } }
        elseif ([string]$nic['managedBy']) { @{ Kind = 'Network interface (service-managed)'; Attached = ([string]$nic['managedBy'] -split '/')[-1] } }
        else { @{ Kind = 'Network interface (not attached)'; Attached = '' } }
        $owner['Resource'] = [string]$nic['name']; $owner['ResourceId'] = [string]$nic['id']; $owner['ResourceGroup'] = [string]$nic['resourceGroup']; $owner['SubscriptionId'] = [string]$nic['subscriptionId']
        foreach ($c in @($nic['ipConfigurations']) | Where-Object { $_ }) { & $addConfig $c $owner }
    }
    foreach ($nic in $ScaleSetInterface) {
        if (-not $nic) { continue }
        $id = [string]$nic['id']
        $set = if ($id -match '/virtualmachinescalesets/([^/]+)/virtualmachines/([^/]+)/') { @($Matches[1], $Matches[2]) } else { @(($id -split '/')[-1], '') }
        $owner = @{ Kind = 'VM scale set instance'; Attached = $set[0]; Resource = "$($set[0])_$($set[1])"; ResourceId = $id; ResourceGroup = [string]$nic['resourceGroup']; SubscriptionId = [string]$nic['subscriptionId'] }
        foreach ($c in @($nic['ipConfigurations']) | Where-Object { $_ }) { & $addConfig $c $owner }
    }
    $kindOf = @{
        'microsoft.network/loadbalancers' = 'Load balancer'; 'microsoft.network/azurefirewalls' = 'Azure Firewall'; 'microsoft.network/bastionhosts' = 'Bastion'
        'microsoft.network/virtualnetworkgateways' = 'VPN / ExpressRoute gateway'; 'microsoft.network/applicationgateways' = 'Application gateway'; 'microsoft.network/privatelinkservices' = 'Private Link service'
    }
    foreach ($res in $IpResource) {
        if (-not $res) { continue }
        $type = & $lower $res['type']
        $owner = @{ Kind = $(if ($kindOf.ContainsKey($type)) { $kindOf[$type] } else { $type }); Attached = ''; Resource = [string]$res['name']; ResourceId = [string]$res['id']; ResourceGroup = [string]$res['resourceGroup']; SubscriptionId = [string]$res['subscriptionId'] }
        foreach ($c in @($res['configs']) | Where-Object { $_ }) { & $addConfig $c $owner }
    }
    # An address whose owner wasn't read: named from its ID (…/providers/<type>/<name>/…).
    $guess = {
        param([string] $Id)
        $parts = $Id -split '/'
        $i = [array]::IndexOf(@($parts | ForEach-Object { $_.ToLowerInvariant() }), 'providers')
        $type = if ($i -ge 0 -and $parts.Count -gt $i + 3) { "$($parts[$i + 1])/$($parts[$i + 2])".ToLowerInvariant() } else { '' }
        $kind = if ($type -eq 'microsoft.network/networkinterfaces') { 'Network interface' } elseif ($type -eq 'microsoft.compute/virtualmachinescalesets') { 'VM scale set instance' } elseif ($kindOf.ContainsKey($type)) { $kindOf[$type] } elseif ($type) { $type } else { 'Unknown' }
        @{ Kind = $kind; Attached = ''; Resource = $(if ($i -ge 0 -and $parts.Count -gt $i + 3) { $parts[$i + 3] } else { $Id }); ResourceId = $(if ($i -ge 0) { ($parts[0..([Math]::Min($i + 3, $parts.Count - 1))]) -join '/' } else { $Id }); ResourceGroup = $(if ($parts.Count -gt 4) { $parts[4] } else { '' }); SubscriptionId = $(if ($parts.Count -gt 2) { $parts[2] } else { '' }); Ip = ''; Allocation = ''; PublicIp = '' }
    }

    # --- Networks: virtual networks, Virtual WAN hubs, external ranges ----------------------------------------------
    $networks = [System.Collections.Generic.List[object]]::new()
    $subnets = [System.Collections.Generic.List[object]]::new()
    $ipRows = [System.Collections.Generic.List[object]]::new()
    $ranges = [System.Collections.Generic.List[object]]::new()   # every IPv4 prefix: for blocks and overlaps
    $peers = @{}
    $networkOf = @{}
    $placement = {
        param([object[]] $Prefixes)
        $v4 = @($Prefixes | ForEach-Object { & $parse $_ } | Where-Object { $_.Valid -and $_.Version -eq 4 })
        $inside = @($v4 | Where-Object { @(& $containing $_).Count })
        $blocksIn = @($inside | ForEach-Object { & $containing $_ } | Group-Object -Property { "$($_.Space)|$($_.Name)" } | ForEach-Object { $_.Group[0] })
        @{
            V4 = $v4; Blocks = $blocksIn
            Status = $(if (-not $v4.Count) { 'IPv6 only' } elseif ($inside.Count -eq $v4.Count) { 'Managed' } elseif ($inside.Count -or @($v4 | Where-Object { @(& $touching $_).Count }).Count) { 'Partly managed' } else { 'Unmanaged' })
        }
    }
    foreach ($vnet in $VirtualNetwork) {
        if (-not $vnet) { continue }
        $vid = & $lower $vnet['id']
        $vname = [string]$vnet['name']
        $prefixes = @(@($vnet['prefixes']) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        $place = & $placement $prefixes
        $peerNames = [System.Collections.Generic.List[string]]::new()
        $peers[$vid] = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($peering in @($vnet['peerings']) | Where-Object { $_ }) {
            $remote = & $lower (& $at $peering 'properties', 'remoteVirtualNetwork', 'id')
            if ($remote) { $null = $peers[$vid].Add($remote); $peerNames.Add(($remote -split '/')[-1]) }
        }
        $dns = @(@($vnet['dnsServers']) | Where-Object { $_ })
        $tags = $vnet['tags']
        $reservation = if ($tags -is [System.Collections.IDictionary]) { [string]$(foreach ($k in $tags.Keys) { if ([string]$k -in 'X-IPAM-RES-ID', 'ipam-res-id') { $tags[$k] } }) } else { '' }
        $firstBlock = @($place.Blocks) | Select-Object -First 1
        $spaceName = if ($firstBlock) { $firstBlock.Space } else { '' }
        foreach ($r in $place.V4) { $ranges.Add(@{ Start = $r.Start; End = $r.End; Prefix = $r.Prefix; Network = $vname; Id = $vid; Kind = 'Virtual network'; Space = $spaceName }) }

        # Its subnets, and every address in each.
        $netUsed = 0; $netUsable = 0; $netSubnetSize = [long]0; $subnetCount = 0
        foreach ($subnet in @($vnet['subnets']) | Where-Object { $_ }) {
            $sp = & $at $subnet 'properties'
            $sname = [string]$subnet['name']
            $sprefixes = @(@(& $at $sp 'addressPrefix') + @(& $at $sp 'addressPrefixes') | Where-Object { $_ } | ForEach-Object { [string]$_ } | Select-Object -Unique)
            $s4 = @($sprefixes | ForEach-Object { & $parse $_ } | Where-Object { $_.Valid -and $_.Version -eq 4 }) | Select-Object -First 1
            $size = if ($s4) { [long]$s4.Size } else { [long]0 }
            $usable = [Math]::Max([long]0, $size - 5)
            $ids = @(@(& $at $sp 'ipConfigurations') + @(& $at $sp 'applicationGatewayIPConfigurations') | Where-Object { $_ } | ForEach-Object { & $lower $_['id'] } | Where-Object { $_ } | Select-Object -Unique)
            $kinds = @{}
            foreach ($id in $ids) {
                $owner = if ($configs.ContainsKey($id)) { $configs[$id] } else { & $guess $id }
                if (-not $kinds.ContainsKey($owner.Kind)) { $kinds[$owner.Kind] = 0 }
                $kinds[$owner.Kind]++
                $ipRows.Add([pscustomobject][ordered]@{
                        PSTypeName = 'AAC.IpamIpAddress'; Space = $spaceName; Network = $vname; Subnet = $sname; PrivateIp = $owner.Ip; Allocation = $owner.Allocation
                        Kind = $owner.Kind; Resource = $owner.Resource; Attached = $owner.Attached; PublicIp = $owner.PublicIp
                        Subscription = (& $subName $owner.SubscriptionId); ResourceGroup = $owner.ResourceGroup; SubnetPrefix = $(if ($s4) { $s4.Prefix } else { ($sprefixes -join ', ') })
                        ResourceId = $owner.ResourceId; IpValue = (& $ipValue $owner.Ip)
                    })
            }
            $used = $ids.Count
            $delegations = @(@(& $at $sp 'delegations') | Where-Object { $_ } | ForEach-Object { [string](& $at $_ 'properties', 'serviceName') })
            $purpose = switch -Regex ($sname) {
                '^GatewaySubnet$' { 'VPN / ExpressRoute gateway'; break }
                '^AzureFirewall(Management)?Subnet$' { 'Azure Firewall'; break }
                '^AzureBastionSubnet$' { 'Bastion'; break }
                '^RouteServerSubnet$' { 'Route Server'; break }
                default {
                    if ($delegations.Count) { "Delegated: $($delegations -join ', ')" }
                    elseif (@(& $at $sp 'applicationGatewayIPConfigurations') | Where-Object { $_ }) { 'Application gateway' }
                    elseif ($used -and $kinds.Count -eq 1 -and $kinds.ContainsKey('Private endpoint')) { 'Private endpoints' }
                    elseif ($used) { 'Workloads' }
                    else { 'Empty' }
                }
            }
            $usedPercent = & $percent $used $usable
            $subnetStatus = if (-not $s4) { 'IPv6 only' } elseif (-not $used) { 'Empty' } else { & $status $usedPercent ($used -ge $usable) }
            $subnets.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.IpamSubnet'; Space = $spaceName; Network = $vname; Subnet = $sname; Prefix = $(if ($s4) { $s4.Prefix } else { ($sprefixes -join ', ') })
                    Range = $(if ($s4) { & $rangeText $s4.Start $s4.End } else { '' })
                    UsableRange = $(if ($s4 -and $size -ge 8) { & $rangeText ($s4.Start + 4) ($s4.End - 1) } else { '' })
                    Size = $size; Usable = $usable; Used = $used; Available = [Math]::Max([long]0, $usable - $used); UsedPercent = $usedPercent; Status = $subnetStatus
                    Purpose = $purpose; Delegation = $delegations -join ', '
                    Kinds = (@($kinds.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Key | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ')
                    Subscription = (& $subName $vnet['subscriptionId']); ResourceGroup = [string]$vnet['resourceGroup']; ResourceId = [string]$subnet['id']
                })
            if ($s4 -and $subnetStatus -in 'Full', 'Critical' -and $purpose -notmatch '^(VPN|Azure Firewall|Bastion|Route Server)') {
                & $find $(if ($subnetStatus -eq 'Full') { 'High' } else { 'Medium' }) 'Capacity' $spaceName "$vname / $sname" $(if ($subnetStatus -eq 'Full') { 'Subnet full' } else { 'Subnet nearly full' }) "$used of $usable usable addresses taken ($usedPercent%) in $($s4.Prefix)." 'Add a subnet from the network''s free space (or widen the network), and move new workloads there.' ([string]$subnet['id'])
            }
            elseif ($s4 -and $subnetStatus -eq 'Warning' -and $purpose -notmatch '^(VPN|Azure Firewall|Bastion|Route Server)') {
                & $find 'Low' 'Capacity' $spaceName "$vname / $sname" 'Subnet filling up' "$used of $usable usable addresses taken ($usedPercent%) in $($s4.Prefix)." 'Plan the next subnet before this one fills - scale-outs and upgrades need spare addresses.' ([string]$subnet['id'])
            }
            $netUsed += $used; $netUsable += $usable; $netSubnetSize += $size; $subnetCount++
        }
        $netSize = (& $unionSize $place.V4)
        $unattached = @($ipRows | Where-Object { $_.Network -eq $vname -and $_.Kind -eq 'Network interface (not attached)' }).Count
        if ($unattached) { & $find 'Low' 'Hygiene' $spaceName $vname 'Unattached network interfaces hold addresses' "$unattached network interface(s) attached to nothing keep an address each." 'Delete them if nothing will use them (Get-AACUnusedResource lists them).' ([string]$vnet['id']) }
        $row = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.IpamNetwork'; Space = $spaceName; Block = (@($place.Blocks | ForEach-Object { $_.Name }) -join ', '); Network = $vname; Kind = 'Virtual network'
            Prefixes = $prefixes -join ', '; Status = $place.Status; Size = $netSize; Subnets = $subnetCount
            Usable = $netUsable; Used = $netUsed; Available = [Math]::Max(0, $netUsable - $netUsed); UsedPercent = (& $percent $netUsed $netUsable)
            Unallocated = [Math]::Max([long]0, $netSize - $netSubnetSize)
            DnsServers = $(if ($dns.Count) { $dns -join ', ' } else { 'Azure-provided' }); Peerings = $peerNames.Count; PeeredWith = $peerNames -join ', '
            Overlaps = 0; IpamReservation = $reservation
            Subscription = (& $subName $vnet['subscriptionId']); ResourceGroup = [string]$vnet['resourceGroup']; Location = [string]$vnet['location']; Description = ''; ResourceId = [string]$vnet['id']
        }
        $networks.Add($row); $networkOf[$vid] = $row
    }
    foreach ($hubRow in $Hub) {
        if (-not $hubRow) { continue }
        $hid = & $lower $hubRow['id']
        $prefix = [string]$hubRow['prefix']
        $place = & $placement @($prefix)
        $firstBlock = @($place.Blocks) | Select-Object -First 1
        $spaceName = if ($firstBlock) { $firstBlock.Space } else { '' }
        foreach ($r in $place.V4) { $ranges.Add(@{ Start = $r.Start; End = $r.End; Prefix = $r.Prefix; Network = [string]$hubRow['name']; Id = $hid; Kind = 'Virtual WAN hub'; Space = $spaceName }) }
        $row = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.IpamNetwork'; Space = $spaceName; Block = (@($place.Blocks | ForEach-Object { $_.Name }) -join ', '); Network = [string]$hubRow['name']; Kind = 'Virtual WAN hub'
            Prefixes = $prefix; Status = $place.Status; Size = (& $unionSize $place.V4); Subnets = 0; Usable = $null; Used = $null; Available = $null; UsedPercent = $null; Unallocated = $null
            DnsServers = ''; Peerings = 0; PeeredWith = ''; Overlaps = 0; IpamReservation = ''
            Subscription = (& $subName $hubRow['subscriptionId']); ResourceGroup = [string]$hubRow['resourceGroup']; Location = [string]$hubRow['location']
            Description = "Virtual WAN: $(([string]$hubRow['vwan'] -split '/')[-1])"; ResourceId = [string]$hubRow['id']
        }
        $networks.Add($row); $networkOf[$hid] = $row
    }
    foreach ($ext in @($Plan.External)) {
        $range = & $parse $ext.Cidr
        $place = & $placement @($ext.Cidr)
        $firstBlock = @($place.Blocks) | Select-Object -First 1
        $spaceName = if ($ext.Space) { $ext.Space } elseif ($firstBlock) { $firstBlock.Space } else { '' }
        $key = "external|$($ext.Name)"
        $ranges.Add(@{ Start = $range.Start; End = $range.End; Prefix = $ext.Cidr; Network = $ext.Name; Id = $key; Kind = 'External'; Space = $spaceName })
        $row = [pscustomobject][ordered]@{
            PSTypeName = 'AAC.IpamNetwork'; Space = $spaceName; Block = (@($place.Blocks | ForEach-Object { $_.Name }) -join ', '); Network = $ext.Name; Kind = 'External'
            Prefixes = $ext.Cidr; Status = $place.Status; Size = [long]$range.Size; Subnets = 0; Usable = $null; Used = $null; Available = $null; UsedPercent = $null; Unallocated = $null
            DnsServers = ''; Peerings = 0; PeeredWith = ''; Overlaps = 0; IpamReservation = ''; Subscription = ''; ResourceGroup = ''; Location = ''; Description = $ext.Description; ResourceId = ''
        }
        $networks.Add($row); $networkOf[$key] = $row
    }
    foreach ($row in $networks) {
        if ($row.Kind -eq 'External') { continue }
        if ($row.Status -eq 'Unmanaged') {
            & $find 'Medium' 'Plan' '' $row.Network $(if ($Plan.Default) { 'Public address space used privately' } else { 'Network outside the plan' }) "$($row.Prefixes) is in no block of $(if ($Plan.Default) { 'the private ranges' } else { 'the address plan' })." $(if ($Plan.Default) { 'Use private (RFC 1918) addresses: public ranges used inside Azure shadow the real internet services that own them.' } else { 'Add its range to a block of the plan, or re-address the network into one.' }) $row.ResourceId
        }
        elseif ($row.Status -eq 'Partly managed') {
            & $find 'Medium' 'Plan' $row.Space $row.Network 'Network straddles the plan' "Some of $($row.Prefixes) is outside every block (or crosses a block's edge)." 'Re-address the prefix that falls outside, or widen the block - allocations from the block can collide with it.' $row.ResourceId
        }
        if (@($row.Block -split ', ' | Where-Object { $_ }).Count -gt 1) {
            & $find 'Info' 'Plan' $row.Space $row.Network 'Network spans blocks' "Its prefixes come from $($row.Block)." 'Fine if intended - track one reservation per block (Azure IPAM needs one X-IPAM-RES-ID per block).' $row.ResourceId
        }
        if ($row.IpamReservation -and $row.Status -eq 'Unmanaged') {
            & $find 'Low' 'Plan' '' $row.Network 'IPAM reservation tag on an unplanned network' "Tagged X-IPAM-RES-ID = $($row.IpamReservation), but its range is in no block of the plan." 'Check the plan matches the Azure IPAM spaces and blocks, or remove the stale tag.' $row.ResourceId
        }
    }

    # --- Overlaps: a sweep over the ranges by start address ---------------------------------------------------------
    $overlaps = [System.Collections.Generic.List[object]]::new()
    $active = [System.Collections.Generic.List[object]]::new()
    foreach ($r in @($ranges | Sort-Object -Property { $_.Start }, { -$_.End })) {
        for ($i = $active.Count - 1; $i -ge 0; $i--) { if ($active[$i].End -lt $r.Start) { $active.RemoveAt($i) } }
        foreach ($a in $active) {
            if ($a.Id -eq $r.Id) { continue }
            $peered = ($peers.ContainsKey($a.Id) -and $peers[$a.Id].Contains($r.Id)) -or ($peers.ContainsKey($r.Id) -and $peers[$r.Id].Contains($a.Id))
            $external = 'External' -in $a.Kind, $r.Kind
            $hubbed = 'Virtual WAN hub' -in $a.Kind, $r.Kind
            $severity = if ($peered) { 'High' } elseif ($external -or $hubbed) { 'Medium' } else { 'Low' }
            $from = [Math]::Max([long]$a.Start, [long]$r.Start); $to = [Math]::Min([long]$a.End, [long]$r.End)
            $impact = if ($peered) { 'Peered networks with overlapping addresses: traffic to the shared range goes to one of them only.' }
            elseif ($external) { 'Overlaps an external (on-premises or partner) range: the two can''t reach each other over VPN or ExpressRoute, and routes conflict.' }
            elseif ($hubbed) { 'Overlaps a Virtual WAN hub''s range: the network can''t connect to that hub.' }
            else { 'They can never be peered or connected to the same hub without re-addressing one.' }
            $overlaps.Add([pscustomobject][ordered]@{
                    PSTypeName = 'AAC.IpamOverlap'; Severity = $severity; Space = $(if ($a.Space) { $a.Space } else { $r.Space })
                    NetworkA = $a.Network; KindA = $a.Kind; PrefixA = $a.Prefix; NetworkB = $r.Network; KindB = $r.Kind; PrefixB = $r.Prefix
                    Overlap = (& $rangeText $from $to); Addresses = $to - $from + 1; Peered = $peered; Impact = $impact
                })
            foreach ($id in $a.Id, $r.Id) { if ($networkOf.ContainsKey($id)) { $networkOf[$id].Overlaps++ } }
            & $find $severity 'Overlap' $(if ($a.Space) { $a.Space } else { $r.Space }) "$($a.Network) / $($r.Network)" $(if ($peered) { 'Overlapping peered networks' } elseif ($external) { 'Overlaps an external range' } elseif ($hubbed) { 'Overlaps a Virtual WAN hub' } else { 'Overlapping address space' }) "$($a.Prefix) ($($a.Network)) and $($r.Prefix) ($($r.Network)) share $(& $rangeText $from $to)." $(if ($peered -or $external -or $hubbed) { 'Re-address one side - the overlap breaks routing today.' } else { 'Re-address one of them before they need to talk, or keep them isolated on purpose.' })
        }
        $active.Add($r)
    }

    # --- Blocks: allocation, free space, the next ranges ------------------------------------------------------------
    $blockRows = [System.Collections.Generic.List[object]]::new()
    $freeRows = [System.Collections.Generic.List[object]]::new()
    $nextRows = [System.Collections.Generic.List[object]]::new()
    # The sizes in the order given: the first is the one each block's row and the tiles show.
    $primary = @($NextAvailable | Select-Object -Unique)
    foreach ($b in $blocks) {
        $inBlock = @($ranges | Where-Object { $_.Start -le $b.End -and $b.Start -le $_.End })
        $clipped = @($inBlock | ForEach-Object { @{ Start = [Math]::Max([long]$_.Start, [long]$b.Start); End = [Math]::Min([long]$_.End, [long]$b.End) } })
        $allocated = & $unionSize $clipped
        $free = @(ConvertTo-AACCidrRange -Space $b.Cidr -Used @($inBlock | ForEach-Object { $_.Prefix }))
        $allocatedPercent = & $percent $allocated $b.Size
        $names = @($inBlock | ForEach-Object { $_.Network } | Select-Object -Unique)
        $vnetNames = @($inBlock | Where-Object { $_.Kind -ne 'External' } | ForEach-Object { $_.Id } | Select-Object -Unique)
        $usedIps = @($ipRows | Where-Object { $ip = & $ipValue $_.PrivateIp; $ip -ge $b.Start -and $ip -le $b.End }).Count
        $fitsOf = { param([int] $Length) [long]$total = 0; foreach ($f in $free) { if ($f.Length -le $Length) { $total += [long][Math]::Pow(2, $Length - $f.Length) } }; $total }
        $candidatesOf = {
            param([int] $Length)
            $fitting = @($free | Where-Object { $_.Length -le $Length })
            $best = @($fitting | Sort-Object -Property @{ Expression = { $_.Length }; Descending = $true }, Start) | Select-Object -First 1
            $lowest = @($fitting | Sort-Object -Property Start) | Select-Object -First 1
            @(if ($best) { @{ Fit = 'Best fit'; From = $best; Cidr = (ConvertTo-AACCidrRange -Start $best.Start -Length $Length); Start = [long]$best.Start } }
                if ($lowest -and (-not $best -or $lowest.Start -ne $best.Start)) { @{ Fit = 'Lowest address'; From = $lowest; Cidr = (ConvertTo-AACCidrRange -Start $lowest.Start -Length $Length); Start = [long]$lowest.Start } })
        }
        $firstSize = if ($primary.Count) { $primary[0] } else { 24 }
        $firstCandidate = @(& $candidatesOf $firstSize) | Select-Object -First 1
        $largest = @($free | Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, Start) | Select-Object -First 1
        $blockStatus = & $status $allocatedPercent (-not $free.Count)
        if (-not $names.Count) { $blockStatus = 'Unused' }
        $blockRows.Add([pscustomobject][ordered]@{
                PSTypeName = 'AAC.IpamBlock'; Space = $b.Space; Block = $b.Name; Cidr = $b.Cidr; Range = (& $rangeText $b.Start $b.End); Size = [long]$b.Size
                Networks = $names.Count; NetworkNames = (@($names | Select-Object -First 12) -join ', ') + $(if ($names.Count -gt 12) { ", and $($names.Count - 12) more" } else { '' })
                Allocated = $allocated; AllocatedPercent = $allocatedPercent; Free = [long]$b.Size - $allocated
                LargestFree = $(if ($largest) { $largest.Prefix } else { '' }); FreeRanges = (@($free | Sort-Object -Property @{ Expression = { $_.Size }; Descending = $true }, Start | Select-Object -First 8 | ForEach-Object { $_.Prefix }) -join ', ')
                FreeRangeCount = $free.Count; NextSize = "/$firstSize"; Next = $(if ($firstCandidate) { $firstCandidate.Cidr } else { '' }); Fits = (& $fitsOf $firstSize)
                IpsUsed = $usedIps; Status = $blockStatus; Description = $b.Description; VirtualNetworks = $vnetNames.Count
            })
        foreach ($f in @($free | Sort-Object -Property Start)) {
            $freeRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.IpamFreeRange'; Space = $b.Space; Block = $b.Name; FreeRange = $f.Prefix; Range = (& $rangeText $f.Start ($f.Start + $f.Size - 1)); Addresses = [long]$f.Size; Length = "/$($f.Length)"; Start = [long]$f.Start })
        }
        foreach ($length in $primary) {
            $fits = & $fitsOf $length
            foreach ($c in @(& $candidatesOf $length)) {
                $cr = & $parse $c.Cidr
                $nextRows.Add([pscustomobject][ordered]@{
                        PSTypeName = 'AAC.IpamNextAvailable'; Space = $b.Space; Block = $b.Name; Size = "/$length"; Candidate = $c.Cidr; Range = (& $rangeText $cr.Start $cr.End); Addresses = [long]$cr.Size
                        Fit = $c.Fit; FromFreeRange = $c.From.Prefix; Fits = $fits
                        Why = $(if ($c.Fit -eq 'Best fit') { "The smallest free range a /$length fits ($($c.From.Prefix)) - larger free ranges stay whole for larger networks." } else { 'The lowest free address in the block.' })
                    })
            }
            if (-not $fits) {
                $nextRows.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.IpamNextAvailable'; Space = $b.Space; Block = $b.Name; Size = "/$length"; Candidate = ''; Range = ''; Addresses = $null; Fit = 'No room'; FromFreeRange = ''; Fits = 0; Why = "No free /$length is left in $($b.Cidr)." })
            }
        }
        if ($blockStatus -in 'Full', 'Critical') {
            & $find 'High' 'Capacity' $b.Space $b.Name $(if ($blockStatus -eq 'Full') { 'Block full' } else { 'Block nearly full' }) "$allocatedPercent% of $($b.Cidr) is allocated; largest free range $(if ($largest) { $largest.Prefix } else { 'none' })." 'Add a block to the space (or reclaim unused networks) before the next request fails.'
        }
        elseif ($blockStatus -eq 'Warning') {
            & $find 'Medium' 'Capacity' $b.Space $b.Name 'Block filling up' "$allocatedPercent% of $($b.Cidr) is allocated ($WarningPercent% warns)." 'Plan the next block now - and check the largest free range still fits the network sizes you hand out.'
        }
        elseif ($blockStatus -eq 'Unused') {
            & $find 'Info' 'Plan' $b.Space $b.Name 'Unused block' "No network or external range is in $($b.Cidr)." 'Fine for a reserve; remove it from the plan if it is not meant for Azure.'
        }
    }

    # --- Spaces ---------------------------------------------------------------------------------------------------
    $rank = @{ Full = 0; Critical = 1; Warning = 2; OK = 3; Unused = 4; Empty = 5 }
    $spaceRows = @(foreach ($s in @($Plan.Spaces)) {
            $mine = @($blockRows | Where-Object { $_.Space -eq $s.Name })
            $size = [long]0; $allocated = [long]0; foreach ($m in $mine) { $size += $m.Size; $allocated += $m.Allocated }
            $spaceNetworks = @($networks | Where-Object { $_.Space -eq $s.Name })
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.IpamSpace'; Space = $s.Name; Description = $s.Description; Blocks = $mine.Count; Size = $size; Allocated = $allocated; AllocatedPercent = (& $percent $allocated $size); Free = $size - $allocated
                Networks = $spaceNetworks.Count; Subnets = @($subnets | Where-Object { $_.Space -eq $s.Name }).Count; IpsUsed = @($ipRows | Where-Object { $_.Space -eq $s.Name }).Count
                Overlaps = @($overlaps | Where-Object { $_.Space -eq $s.Name }).Count
                Status = $(@($mine | Sort-Object -Property { $rank[$_.Status] }) | Select-Object -First 1 | ForEach-Object { $_.Status })
                Findings = @($findings | Where-Object { $_.Space -eq $s.Name }).Count
            }
        })

    # --- CIDR checks ----------------------------------------------------------------------------------------------
    $checks = @(foreach ($cidr in @($TestCidr | Where-Object { $_ })) {
            $c = & $parse $cidr
            if (-not $c.Valid -or $c.Version -ne 4) { throw "Azure Admin Console can't check '$cidr': give an IPv4 CIDR range such as 10.20.8.0/22." }
            $hits = @($ranges | Where-Object { $_.Start -le $c.End -and $c.Start -le $_.End })
            $whole = @($hits | Where-Object { $_.Start -le $c.Start -and $c.End -le $_.End })
            $inBlocks = @(& $containing $c)
            $state = if ($whole.Count) { 'Taken' } elseif ($hits.Count) { 'Partly taken' } elseif ($inBlocks.Count) { 'Free' } else { 'Free, outside every block' }
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.IpamCidrCheck'; Cidr = (ConvertTo-AACCidrRange -Start $c.Start -Length $c.Length); Range = (& $rangeText $c.Start $c.End); Addresses = [long]$c.Size; Status = $state
                Space = (@($inBlocks | ForEach-Object { $_.Space } | Select-Object -Unique) -join ', '); Block = (@($inBlocks | ForEach-Object { $_.Name }) -join ', ')
                ConflictsWith = (@($hits | ForEach-Object { "$($_.Network) ($($_.Prefix))" } | Select-Object -Unique) -join ', ')
                Detail = $(switch ($state) { 'Taken' { 'Wholly inside a range already in use.' } 'Partly taken' { 'Overlaps a range in use - a smaller or shifted range might fit.' } 'Free' { 'Free, inside the plan.' } default { 'Free in Azure, but in no block of the plan - check it isn''t used on-premises.' } })
            }
        })

    # --- The tree: space > block > network > subnet ---------------------------------------------------------------
    $tone = @{ Full = 'bad'; Critical = 'bad'; Warning = 'warn'; OK = 'good'; Unused = 'neutral'; Empty = 'neutral'; Managed = 'good'; 'Partly managed' = 'warn'; Unmanaged = 'bad'; 'IPv6 only' = 'neutral' }
    $subnetNode = {
        param($s)
        @{ l = 'sn'; n = $s.Subnet; d = "$($s.Prefix) - $($s.Purpose)"; f = @{ table = 'subnets'; filters = @{ Network = $s.Network; Subnet = $s.Subnet } }
            pl = @(, @("$($s.Used)/$($s.Usable) used", $tone[$s.Status], "$($s.Available) available ($($s.Status))")) }
    }
    $networkNode = {
        param($n)
        $kids = @($subnets | Where-Object { $_.Network -eq $n.Network } | ForEach-Object { & $subnetNode $_ })
        $node = @{ l = 'nw'; n = $n.Network; d = "$($n.Prefixes) - $($n.Kind)"; f = @{ table = 'networks'; filters = @{ Network = $n.Network } }
            pl = @(, @($n.Status, $tone[$n.Status], "$($n.Subscription) / $($n.ResourceGroup)")) }
        if ($null -ne $n.UsedPercent) { $node.pl += , @("$($n.UsedPercent)% of subnets used", $(if ($n.UsedPercent -ge $CriticalPercent) { 'bad' } elseif ($n.UsedPercent -ge $WarningPercent) { 'warn' } else { 'info' }), "$($n.Used) of $($n.Usable) usable addresses") }
        if ($n.Overlaps) { $node.pl += , @("$($n.Overlaps) overlap(s)", 'bad', 'See the Overlaps tab') }
        if ($kids.Count) { $node.k = $kids }
        $node
    }
    $treeSpaces = @(foreach ($s in $spaceRows) {
            @{ l = 'sp'; n = $s.Space; d = "$($s.Blocks) block(s), $($s.Networks) network(s)"; f = @{ table = 'blocks'; filters = @{ Space = $s.Space } }
                pl = @(, @("$($s.AllocatedPercent)% allocated", $tone[[string]$s.Status], "$('{0:N0}' -f $s.Free) addresses free"))
                k = @(foreach ($b in @($blockRows | Where-Object { $_.Space -eq $s.Space })) {
                        $inside = @($networks | Where-Object { @($_.Block -split ', ') -contains $b.Block -and $_.Space -eq $b.Space })
                        $node = @{ l = 'bl'; n = "$($b.Block)"; d = "$($b.Cidr) - $($b.Networks) network(s), next /$($primary[0]): $(if ($b.Next) { $b.Next } else { 'none' })"; f = @{ table = 'blocks'; filters = @{ Space = $b.Space; Block = $b.Block } }
                            pl = @(, @("$($b.AllocatedPercent)% allocated", $tone[$b.Status], "Largest free: $($b.LargestFree)")) }
                        $kids = @($inside | ForEach-Object { & $networkNode $_ })
                        if ($kids.Count) { $node.k = $kids }
                        $node
                    })
            }
        })
    $outside = @($networks | Where-Object { -not $_.Space -and $_.Status -ne 'Managed' })
    if ($outside.Count) { $treeSpaces += @{ l = 'sp'; n = 'Outside the plan'; d = "$($outside.Count) network(s) in no block"; x = $true; k = @($outside | ForEach-Object { & $networkNode $_ }); f = @{ table = 'networks'; filters = @{ Status = 'Unmanaged' } } } }
    $tree = @{
        Title = 'Address plan'; OpenTo = 'bl'; Top = $true; Placeholder = 'Find a space, block, network or subnet'
        Levels = @{ root = @('Plan', 'info'); sp = @('Space', 'violet'); bl = @('Block', 'info'); nw = @('Network', 'good'); sn = @('Subnet', 'neutral') }
        Order = @('root', 'sp', 'bl', 'nw', 'sn'); Buttons = @(@('spaces', 'sp'), @('blocks', 'bl'), @('networks', 'nw'), @('subnets', 'sn'))
        Root = @{ l = 'root'; n = $Plan.Source; d = "$($spaceRows.Count) space(s), $($blockRows.Count) block(s)"; k = $treeSpaces }
    }

    $severityRank = @{ High = 0; Medium = 1; Low = 2; Info = 3 }
    $allocatedTotal = [long]0; $sizeTotal = [long]0; foreach ($b in $blockRows) { $allocatedTotal += $b.Allocated; $sizeTotal += $b.Size }
    @{
        Plan          = $Plan
        Spaces        = $spaceRows
        Blocks        = $blockRows.ToArray()
        Networks      = @($networks | Sort-Object -Property @{ Expression = { $_.Space -eq '' } }, Space, Block, Network)
        Subnets       = @($subnets | Sort-Object -Property Space, Network, @{ Expression = { (& $parse ([string]$_.Prefix)).Start } })
        IpAddresses   = @($ipRows | Sort-Object -Property Network, Subnet, IpValue | Select-Object -Property * -ExcludeProperty IpValue | ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'AAC.IpamIpAddress'); $_ })
        Overlaps      = @($overlaps | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] } }, NetworkA, NetworkB)
        FreeRanges    = $freeRows.ToArray()
        NextAvailable = $nextRows.ToArray()
        CidrChecks    = $checks
        Findings      = @($findings | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] } }, Category, Space, Item)
        Tree          = $tree
        Stats         = @{
            Spaces = $spaceRows.Count; Blocks = $blockRows.Count; Networks = @($networks | Where-Object { $_.Kind -ne 'External' }).Count
            VirtualNetworks = @($networks | Where-Object { $_.Kind -eq 'Virtual network' }).Count; Hubs = @($networks | Where-Object { $_.Kind -eq 'Virtual WAN hub' }).Count; External = @($networks | Where-Object { $_.Kind -eq 'External' }).Count
            Managed = @($networks | Where-Object { $_.Kind -ne 'External' -and $_.Status -eq 'Managed' }).Count; Unmanaged = @($networks | Where-Object { $_.Kind -ne 'External' -and $_.Status -eq 'Unmanaged' }).Count
            PartlyManaged = @($networks | Where-Object { $_.Kind -ne 'External' -and $_.Status -eq 'Partly managed' }).Count
            Subnets = $subnets.Count; IpAddresses = $ipRows.Count; Size = $sizeTotal; Allocated = $allocatedTotal; AllocatedPercent = (& $percent $allocatedTotal $sizeTotal)
            NextSize = $(if ($primary.Count) { $primary[0] } else { 24 }); Fits = (& { $t = [long]0; foreach ($b in $blockRows) { $t += $b.Fits }; $t })
            Overlaps = $overlaps.Count; PeeredOverlaps = @($overlaps | Where-Object { $_.Peered }).Count
            High = @($findings | Where-Object { $_.Severity -eq 'High' }).Count; Medium = @($findings | Where-Object { $_.Severity -eq 'Medium' }).Count
            Low = @($findings | Where-Object { $_.Severity -eq 'Low' }).Count; Info = @($findings | Where-Object { $_.Severity -eq 'Info' }).Count
            FullSubnets = @($subnets | Where-Object { $_.Status -in 'Full', 'Critical' }).Count
        }
    }
}
