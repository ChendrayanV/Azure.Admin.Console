function ConvertTo-AACResourceMap {
    <#
    .SYNOPSIS
        Turns Resource Graph rows into the resource map: nested boxes, the
        resources in them and the connections between them - the model the
        map's HTML page lays out with ELK.
    .DESCRIPTION
        Boxes (Clusters), outermost first:
          subscription > resource group > virtual network > subnet
        A resource with an IP configuration in a subnet - a network interface,
        private endpoint, firewall, gateway, Bastion, internal load balancer,
        AKS or API Management - is drawn in that subnet's box, and a virtual
        machine or scale set in the subnet of its first network interface.
        Everything else is drawn in its resource group's box. Rows from
        -External (resources outside the chosen resource groups that a chosen
        one refers to) go in boxes of their own resource groups, marked as
        outside the selection.

        Connections (Edges) come from the resource IDs in each resource's
        properties, each typed by where it was found:
          network      NIC, IP, subnet, NSG, route table, NAT, gateway links -
                       and VNet integration
          peering      virtual network peering (with its state)
          privatelink  a private endpoint to the resource it serves
          route        a route table's next hop (a firewall or appliance IP)
          dns          a private DNS zone linked to a virtual network
          dependency   everything else (an app on its plan, a VM on its disk,
                       a database on its server, ...)
        Back-references (a NIC's virtualMachine, a disk's managedBy, an NSG's
        subnets, ...) are turned around so each link is drawn once, from the
        resource that uses to the one it uses; a link to the box a resource
        is drawn in isn't drawn.

        Resources that are attached to nothing - a network interface without
        a VM or private endpoint, a public IP without a configuration, an
        unattached disk, an NSG or route table on nothing - are flagged
        (Orphan) with the reason.

        NSGs and route tables are what a network engineer reads first, so they
        carry more:
          - each attached one is also a chip on the subnets and NICs it is
            applied to (Chips), and its links to them are drawn only in the
            page's "cards" view (view = 'cards'); a subnet's routes are then
            drawn from the subnet itself ("0.0.0.0/0 via rt-spoke",
            view = 'chips')
          - an NSG's rules (Rules: priority, direction, access, protocol,
            source, ports, destination - application security groups by
            name - custom and default), each scored: 'high' for an allow from
            the internet (*, Internet, 0.0.0.0/0) to every port or to a
            management or database port (SSH, RDP, WinRM, SMB, SQL, ...),
            'medium' for an allow from the internet to a wide port range
          - a route table's routes (Routes), each next hop resolved to the
            resource that has that IP; 'high' when no resource here has it
            (the traffic may be dropped), 'medium' for 0.0.0.0/0 straight to
            the internet; and whether gateway route propagation is off
        A subnet's box also says how many of its addresses are used and what
        it is delegated to; a peering says whether it forwards traffic, offers
        gateway transit or uses the remote gateways.

        Returns a hashtable: Clusters, Nodes, Edges (lists of hashtables, as
        the page reads them) and Stats.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # Resource Graph rows (hashtables: id, name, type, kind, location,
        # resourceGroup, subscriptionId, sku, properties, tags).
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Resource,

        # Rows of resources outside the chosen resource groups that the
        # chosen ones refer to.
        [AllowEmptyCollection()]
        [object[]] $External = @(),

        # Subscription ID -> name.
        [hashtable] $SubscriptionName = @{},

        # Resource type -> icon key (the icon set's 'types').
        [hashtable] $IconType = @{},

        # Icon key -> the product name shown with it.
        [hashtable] $IconLabel = @{},

        # Resource types to leave out; wildcards work.
        [string[]] $ExcludeType = @()
    )

    # --- Helpers -----------------------------------------------------------------------------------
    # Keys from ConvertFrom-Json -AsHashtable are case-sensitive; ARM's aren't.
    function Get-Value($Dictionary, [string] $Key) {
        if ($Dictionary -isnot [System.Collections.IDictionary]) { return $null }
        if ($Dictionary.Contains($Key)) { return $Dictionary[$Key] }
        foreach ($name in $Dictionary.Keys) { if ($name -eq $Key) { return $Dictionary[$name] } }
        $null
    }
    function Get-Path($Dictionary, [string[]] $Keys) {
        $value = $Dictionary
        foreach ($key in $Keys) { $value = Get-Value $value $key; if ($null -eq $value) { return $null } }
        $value
    }
    # Every resource ID in a value, with the property path it was found at.
    $idPattern = '^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/[^/]+/[^/]+/[^/]+'
    function Find-Reference($Value, [string] $Path, $Into) {
        if ($null -eq $Value) { return }
        if ($Value -is [string]) {
            if ($Value -match $idPattern) { $Into.Add([pscustomobject]@{ Path = $Path; Id = $Value.ToLowerInvariant().TrimEnd('/') }) }
            return
        }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in @($Value.Keys)) { Find-Reference $Value[$key] $(if ($Path) { "$Path.$key" } else { [string]$key }) $Into }
            return
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $index = 0
            foreach ($item in $Value) { Find-Reference $item "$Path[$index]" $Into; $index++ }
        }
    }
    $lower = { param($Text) ([string]$Text).ToLowerInvariant() }
    # How many items a property has ($null has none; @($null).Count is 1).
    $count = { param($Value) if ($null -eq $Value) { 0 } else { @($Value).Count } }
    $rgId = { param($Subscription, $Group) "/subscriptions/$(& $lower $Subscription)/resourcegroups/$(& $lower $Group)" }
    $label = {
        param([string] $Type, [string] $Icon)
        # Types that share an icon get their own name.
        $own = @{
            'microsoft.network/privateendpoints' = 'Private Endpoint'; 'microsoft.app/containerapps' = 'Container App'; 'microsoft.app/managedenvironments' = 'Container Apps Environment'
            'microsoft.insights/actiongroups' = 'Action Group'; 'microsoft.insights/metricalerts' = 'Metric Alert'; 'microsoft.insights/scheduledqueryrules' = 'Log Search Alert'
            'microsoft.insights/activitylogalerts' = 'Activity Log Alert'; 'microsoft.alertsmanagement/smartdetectoralertrules' = 'Smart Detector Alert'
            'microsoft.insights/datacollectionrules' = 'Data Collection Rule'; 'microsoft.insights/datacollectionendpoints' = 'Data Collection Endpoint'
            'microsoft.network/privatednszones' = 'Private DNS Zone'; 'microsoft.network/frontdoorwebapplicationfirewallpolicies' = 'Front Door WAF Policy'
            'microsoft.cdn/profiles' = 'Front Door and CDN Profile'; 'microsoft.compute/snapshots' = 'Disk Snapshot'
        }
        if ($own.Contains($Type)) { return $own[$Type] }
        if ($Icon -and $Icon -ne 'resource' -and $IconLabel.Contains($Icon)) { return $IconLabel[$Icon] }
        $last = ($Type -split '/')[-1]
        (($last -creplace '([a-z])([A-Z])', '$1 $2') -replace 's$', '')
    }

    $hidden = @('microsoft.compute/virtualmachines/extensions', 'microsoft.network/privatednszones/virtualnetworklinks', 'microsoft.network/networkwatchers/flowlogs') + @($ExcludeType)
    $isHidden = { param([string] $Type) @($hidden | Where-Object { $Type -like $_ }).Count -gt 0 }

    $folded = @{}
    $clusters = [ordered]@{}
    $nodes = [ordered]@{}
    $edges = [ordered]@{}
    $rows = @{}
    $addCluster = {
        param([string] $Id, [string] $Kind, [string] $Parent, [string] $Name, [string[]] $Detail, [string] $Icon, [bool] $IsExternal)
        if (-not $clusters.Contains($Id)) {
            $clusters[$Id] = @{ id = $Id; kind = $Kind; parent = $Parent; name = $Name; detail = @($Detail | Where-Object { $_ }); icon = $Icon; external = $IsExternal; badges = @(); chips = @() }
        }
    }
    $ensureGroup = {
        param([string] $Subscription, [string] $Group, [bool] $IsExternal)
        $subscriptionKey = "/subscriptions/$(& $lower $Subscription)"
        $subscriptionLabel = if ($SubscriptionName.Contains($Subscription)) { $SubscriptionName[$Subscription] } elseif ($SubscriptionName.Contains((& $lower $Subscription))) { $SubscriptionName[(& $lower $Subscription)] } else { $Subscription }
        & $addCluster $subscriptionKey 'subscription' '' $subscriptionLabel @($Subscription) 'subscription' $false
        $groupKey = & $rgId $Subscription $Group
        & $addCluster $groupKey 'resourcegroup' $subscriptionKey $Group @($(if ($IsExternal) { 'outside the selection' })) 'resourcegroup' $IsExternal
        if (-not $IsExternal -and $clusters[$groupKey].external) { $clusters[$groupKey].external = $false; $clusters[$groupKey].detail = @() }
        $groupKey
    }

    # --- 1. Virtual networks and subnets are boxes ---------------------------------------------------
    $all = @(@($Resource | ForEach-Object { @{ Row = $_; External = $false } }) + @($External | ForEach-Object { @{ Row = $_; External = $true } }))
    foreach ($entry in $all) {
        $row = $entry.Row
        $id = & $lower (Get-Value $row 'id')
        if (-not $id -or $rows.Contains($id)) { continue }
        $rows[$id] = $entry
        $type = & $lower (Get-Value $row 'type')
        if ($type -ne 'microsoft.network/virtualnetworks') { continue }
        $group = & $ensureGroup (Get-Value $row 'subscriptionId') (Get-Value $row 'resourceGroup') $entry.External
        $space = @(Get-Path $row 'properties', 'addressSpace', 'addressPrefixes')
        & $addCluster $id 'vnet' $group (Get-Value $row 'name') @(($space -join ', '), (Get-Value $row 'location')) 'vnet' $entry.External
        $clusters[$id].resourceGroup = Get-Value $row 'resourceGroup'
        $clusters[$id].subscriptionId = Get-Value $row 'subscriptionId'
        $clusters[$id].type = 'microsoft.network/virtualnetworks'
        foreach ($subnet in @(Get-Path $row 'properties', 'subnets')) {
            $subnetId = & $lower (Get-Value $subnet 'id')
            if (-not $subnetId) { continue }
            $prefix = Get-Path $subnet 'properties', 'addressPrefix'
            if (-not $prefix) { $prefix = @(Get-Path $subnet 'properties', 'addressPrefixes') -join ', ' }
            # Addresses in use: IP configurations against what the prefix
            # offers, less the five Azure keeps in every subnet.
            $used = & $count (Get-Path $subnet 'properties', 'ipConfigurations')
            $usable = 0
            $first = ([string]$prefix -split ',')[0].Trim()
            if ($first -match '^\d+\.\d+\.\d+\.\d+/(\d+)$') { $usable = [int]([Math]::Pow(2, 32 - [int]$Matches[1]) - 5) }
            $delegations = @(@(Get-Path $subnet 'properties', 'delegations') | ForEach-Object { [string](Get-Path $_ 'properties', 'serviceName') } | Where-Object { $_ })
            $detail = @($prefix)
            if ($usable -gt 0) { $detail += '{0:N0} of {1:N0} IPs used' -f $used, $usable }
            if ($delegations.Count) { $detail += "delegated to $($delegations -join ', ')" }
            & $addCluster $subnetId 'subnet' $id (Get-Value $subnet 'name') $detail 'subnet' $entry.External
            $clusters[$subnetId].type = 'microsoft.network/virtualnetworks/subnets'
            $clusters[$subnetId].prefix = [string]$prefix
            $clusters[$subnetId].used = $used
            $clusters[$subnetId].usable = $usable
            $clusters[$subnetId].delegations = $delegations
            $clusters[$subnetId].serviceEndpoints = @(@(Get-Path $subnet 'properties', 'serviceEndpoints') | ForEach-Object { [string](Get-Value $_ 'service') } | Where-Object { $_ })
            $clusters[$subnetId].privateEndpointPolicies = [string](Get-Path $subnet 'properties', 'privateEndpointNetworkPolicies')
        }
    }

    # --- 2. Every other resource is a node, in its resource group for now ----------------------------
    foreach ($id in @($rows.Keys)) {
        $entry = $rows[$id]
        $row = $entry.Row
        $type = & $lower (Get-Value $row 'type')
        if ($type -eq 'microsoft.network/virtualnetworks' -or (& $isHidden $type)) { continue }
        # A private endpoint's (or private link service's) own NIC is part of
        # it: the endpoint shows its IP, and links to the NIC go to it.
        if ($type -eq 'microsoft.network/networkinterfaces') {
            $owner = Get-Path $row 'properties', 'privateEndpoint', 'id'
            if (-not $owner) { $owner = Get-Path $row 'properties', 'privateLinkService', 'id' }
            if ($owner) { $folded[$id] = (& $lower $owner); continue }
        }
        $kind = [string](Get-Value $row 'kind')
        $icon = if ($IconType.Contains($type)) { $IconType[$type] } else { 'resource' }
        if ($type -eq 'microsoft.web/sites' -and $kind -match 'functionapp') { $icon = 'functionapp' }
        if ($type -eq 'microsoft.cognitiveservices/accounts' -and $kind -eq 'OpenAI') { $icon = 'openai' }
        $group = & $ensureGroup (Get-Value $row 'subscriptionId') (Get-Value $row 'resourceGroup') $entry.External
        $properties = Get-Value $row 'properties'
        $sku = Get-Value $row 'sku'
        $skuName = if ($sku -is [System.Collections.IDictionary]) { [string](Get-Value $sku 'name') } else { '' }

        # A line or two worth seeing on the map.
        $facts = [System.Collections.Generic.List[string]]::new()
        switch ($type) {
            'microsoft.compute/virtualmachines' {
                $facts.Add([string](Get-Path $properties 'hardwareProfile', 'vmSize'))
                $facts.Add([string](Get-Path $properties 'storageProfile', 'osDisk', 'osType'))
            }
            'microsoft.network/networkinterfaces' {
                $facts.Add(((@(Get-Value $properties 'ipConfigurations') | ForEach-Object { Get-Path $_ 'properties', 'privateIPAddress' } | Where-Object { $_ }) -join ', '))
            }
            'microsoft.network/publicipaddresses' {
                $address = Get-Value $properties 'ipAddress'
                $facts.Add($(if ($address) { [string]$address } else { 'no address' }))
            }
            'microsoft.network/azurefirewalls' {
                $facts.Add(((@(Get-Value $properties 'ipConfigurations') | ForEach-Object { Get-Path $_ 'properties', 'privateIPAddress' } | Where-Object { $_ }) -join ', '))
                $facts.Add([string](Get-Path $properties 'sku', 'tier'))
            }
            'microsoft.network/privateendpoints' {
                $facts.Add(((@(Get-Value $properties 'customDnsConfigs') | ForEach-Object { @(Get-Value $_ 'ipAddresses') } | Where-Object { $_ }) -join ', '))
            }
            'microsoft.compute/disks' {
                $size = Get-Value $properties 'diskSizeGB'
                $facts.Add($(if ($size) { "$size GB" } else { '' }))
                $facts.Add($skuName)
            }
            'microsoft.web/sites' { $facts.Add([string](Get-Value $properties 'defaultHostName')) }
            default { $facts.Add($skuName) }
        }

        # Attached to nothing?
        $orphan = switch ($type) {
            'microsoft.network/networkinterfaces' { if (-not (Get-Value $properties 'virtualMachine') -and -not (Get-Value $properties 'privateEndpoint') -and -not (Get-Value $properties 'privateLinkService')) { 'not attached to a VM or private endpoint' } }
            'microsoft.network/publicipaddresses' { if (-not (Get-Value $properties 'ipConfiguration') -and -not (Get-Value $properties 'natGateway')) { 'not associated with anything' } }
            'microsoft.compute/disks' { if ([string](Get-Value $properties 'diskState') -eq 'Unattached') { 'unattached disk' } }
            'microsoft.network/networksecuritygroups' { if (-not (& $count (Get-Value $properties 'subnets')) -and -not (& $count (Get-Value $properties 'networkInterfaces'))) { 'on no subnet or NIC' } }
            'microsoft.network/routetables' { if (-not (& $count (Get-Value $properties 'subnets'))) { 'on no subnet' } }
        }

        $subscriptionId = [string](Get-Value $row 'subscriptionId')
        $nodes[$id] = @{
            id             = $id
            parent         = $group
            name           = [string](Get-Value $row 'name')
            type           = $type
            typeLabel      = & $label $type $icon
            icon           = $icon
            kind           = $kind
            location       = [string](Get-Value $row 'location')
            resourceGroup  = [string](Get-Value $row 'resourceGroup')
            subscriptionId = $subscriptionId
            subscription   = if ($SubscriptionName.Contains($subscriptionId)) { $SubscriptionName[$subscriptionId] } else { $subscriptionId }
            sku            = $skuName
            facts          = @($facts | Where-Object { $_ })
            tags           = Get-Value $row 'tags'
            orphan         = if ($orphan) { [string]$orphan } else { '' }
            external       = [bool]$entry.External
            chips          = @()
            # NSGs and route tables: shown as a chip ('nsg', 'udr'), on what,
            # how risky, and their rules or routes.
            chip           = ''
            appliedTo      = @()
            risk           = ''
            rules          = @()
            routes         = @()
            propagation    = ''
        }
    }

    # Resolves a referenced ID to what is drawn for it: a node, a box, or the
    # nearest parent that is (an IP configuration -> its NIC, a pool -> its
    # load balancer, a subnet -> its box).
    $resolve = {
        param([string] $Id)
        $candidate = $Id
        while ($candidate -match $idPattern) {
            if ($folded.Contains($candidate) -and $nodes.Contains($folded[$candidate])) { return $folded[$candidate] }
            if ($nodes.Contains($candidate) -or $clusters.Contains($candidate)) { return $candidate }
            $parts = $candidate -split '/'
            if ($parts.Count -le 9) { break }
            $candidate = ($parts[0..($parts.Count - 3)]) -join '/'
        }
        $null
    }
    $ancestors = {
        param([string] $Id)
        $chain = [System.Collections.Generic.List[string]]::new()
        $current = if ($nodes.Contains($Id)) { $nodes[$Id].parent } elseif ($clusters.Contains($Id)) { $clusters[$Id].parent } else { '' }
        while ($current) { $chain.Add($current); $current = if ($clusters.Contains($current)) { $clusters[$current].parent } else { '' } }
        $chain
    }

    # --- 3. Placement: a resource with an IP configuration in a subnet goes in it --------------------
    $references = @{}
    foreach ($id in @($rows.Keys)) {
        $list = [System.Collections.Generic.List[object]]::new()
        Find-Reference (Get-Value $rows[$id].Row 'properties') '' $list
        $references[$id] = $list
    }
    $notPlaced = @('microsoft.web/sites', 'microsoft.network/networksecuritygroups', 'microsoft.network/routetables', 'microsoft.network/natgateways', 'microsoft.storage/storageaccounts', 'microsoft.network/virtualnetworks')
    foreach ($id in @($nodes.Keys)) {
        $node = $nodes[$id]
        if ($node.type -in $notPlaced) { continue }
        $subnet = $references[$id] | Where-Object {
            $_.Path -match '(?i)ipconfiguration|frontendipconfiguration|(^|\.)(subnetid|subnetresourceid|vnetsubnetid)$|subnetids|^subnet\.id$' -and $clusters.Contains($_.Id) -and $clusters[$_.Id].kind -eq 'subnet'
        } | Select-Object -First 1
        if ($subnet) { $node.parent = $subnet.Id }
    }
    # A VM (or scale set) goes where its first network interface is.
    foreach ($id in @($nodes.Keys)) {
        $node = $nodes[$id]
        if ($node.type -ne 'microsoft.compute/virtualmachines') { continue }
        $nic = $references[$id] | Where-Object { $_.Path -match '(?i)networkinterfaces' -and $nodes.Contains($_.Id) } | Select-Object -First 1
        if ($nic -and $clusters.Contains($nodes[$nic.Id].parent) -and $clusters[$nodes[$nic.Id].parent].kind -eq 'subnet') { $node.parent = $nodes[$nic.Id].parent }
    }

    # --- 4. Connections ------------------------------------------------------------------------------
    $backReference = '(?i)(^|\.)(virtualMachine|managedBy|ipConfiguration|ipConfigurations|subnets|networkInterfaces|privateEndpoint|privateEndpoints|privateLinkService|linkedResources|serviceAssociationLinks|resourceNavigationLinks)(\[\d+\])?(\.id)?$'
    $networkPath = '(?i)ipconfiguration|networkinterface|publicipaddress|networksecuritygroup|routetable|subnet|natgateway|virtualnetwork|gateway|frontendip|backendaddresspool|loadbalancer'
    # Candidates first; then one link per pair of ends, the most telling kind
    # winning (a VM and its NIC are 'network', not also 'dependency').
    $candidates = [System.Collections.Generic.List[object]]::new()
    $peeringFlags = @{}
    $addEdge = {
        param([string] $From, [string] $To, [string] $Kind, [string] $Label)
        if (-not $From -or -not $To -or $From -eq $To) { return }
        # Not to the box something is drawn in, nor from a box to what is in it.
        if ($To -in @(& $ancestors $From) -or $From -in @(& $ancestors $To)) { return }
        $candidates.Add(@{ From = $From; To = $To; Kind = $Kind; Label = $Label })
    }
    foreach ($id in @($rows.Keys)) {
        $row = $rows[$id].Row
        $type = & $lower (Get-Value $row 'type')

        # A private DNS zone's link to a virtual network.
        if ($type -eq 'microsoft.network/privatednszones/virtualnetworklinks') {
            $zone = & $resolve (($id -split '/')[0..8] -join '/')
            $vnet = & $resolve (& $lower (Get-Path $row 'properties', 'virtualNetwork', 'id'))
            & $addEdge $zone $vnet 'dns' $(if ([string](Get-Path $row 'properties', 'registrationEnabled') -eq 'True') { 'auto-registration' } else { '' })
            continue
        }
        $self = & $resolve $id
        if (-not $self) { continue }
        foreach ($reference in $references[$id]) {
            # Inside a virtual network, a subnet's own links start from the subnet.
            $from = $self
            if ($type -eq 'microsoft.network/virtualnetworks' -and $reference.Path -match '^subnets\[(\d+)\]') {
                $subnetRow = @(Get-Path $row 'properties', 'subnets')[[int]$Matches[1]]
                $from = & $lower (Get-Value $subnetRow 'id')
            }
            $to = & $resolve $reference.Id
            if (-not $to -or $to -eq $from) { continue }
            $kind = if ($reference.Path -match '(?i)virtualnetworkpeerings') { 'peering' }
            elseif ($reference.Path -match '(?i)privatelinkserviceconnections') { 'privatelink' }
            elseif ($reference.Path -match $networkPath -or ($type -like 'microsoft.network/*' -and ($nodes.Contains($to) -and $nodes[$to].type -like 'microsoft.network/*'))) { 'network' }
            else { 'dependency' }
            $edgeLabel = ''
            if ($kind -eq 'peering') {
                $peering = @(Get-Path $row 'properties', 'virtualNetworkPeerings') | Where-Object { (& $lower (Get-Path $_ 'properties', 'remoteVirtualNetwork', 'id')) -eq $reference.Id } | Select-Object -First 1
                $edgeLabel = [string](Get-Path $peering 'properties', 'peeringState')
                # What the peering lets through, from either side.
                $pairKey = (@($from, $to) | Sort-Object) -join '|'
                if (-not $peeringFlags.Contains($pairKey)) { $peeringFlags[$pairKey] = [System.Collections.Generic.List[string]]::new() }
                foreach ($flag in @(@('allowForwardedTraffic', 'forwarded traffic'), @('allowGatewayTransit', 'gateway transit'), @('useRemoteGateways', 'remote gateway'))) {
                    if ([string](Get-Path $peering 'properties', $flag[0]) -eq 'True' -and -not $peeringFlags[$pairKey].Contains($flag[1])) { $peeringFlags[$pairKey].Add($flag[1]) }
                }
            }
            if ($kind -eq 'dependency' -and $reference.Path -match $backReference) { & $addEdge $to $from $kind $edgeLabel }
            else { & $addEdge $from $to $kind $edgeLabel }
        }
        # A child resource (a database on its server) depends on its parent.
        $parts = $id -split '/'
        if ($parts.Count -gt 9) {
            $parent = & $resolve (($parts[0..($parts.Count - 3)]) -join '/')
            if ($parent) { & $addEdge $self $parent 'dependency' '' }
        }
    }

    # Route tables: where their routes send traffic (a firewall or appliance IP).
    $owners = @{}
    foreach ($id in @($nodes.Keys)) {
        $properties = Get-Value $rows[$id].Row 'properties'
        foreach ($configuration in @(@(Get-Value $properties 'ipConfigurations') + @(Get-Value $properties 'frontendIPConfigurations'))) {
            $address = Get-Path $configuration 'properties', 'privateIPAddress'
            if ($address -and -not $owners.Contains([string]$address)) { $owners[[string]$address] = $id }
        }
    }
    $rank = @{ high = 2; medium = 1 }
    $worst = { param([object[]] $Items) $top = ''; foreach ($item in $Items) { if ($item.risk -and (-not $top -or $rank[$item.risk] -gt $rank[$top])) { $top = $item.risk } }; $top }
    foreach ($id in @($nodes.Keys)) {
        if ($nodes[$id].type -ne 'microsoft.network/routetables') { continue }
        $properties = Get-Value $rows[$id].Row 'properties'
        $routes = foreach ($route in @(Get-Value $properties 'routes')) {
            if ($null -eq $route) { continue }
            $prefix = [string](Get-Path $route 'properties', 'addressPrefix')
            $hopType = [string](Get-Path $route 'properties', 'nextHopType')
            $hop = [string](Get-Path $route 'properties', 'nextHopIpAddress')
            $target = ''
            $risk = ''
            $reason = ''
            if ($hop -and $owners.Contains($hop)) {
                $target = $owners[$hop]
                # A NIC on a VM: the route really goes to the VM.
                $vm = & $lower (Get-Path $rows[$target].Row 'properties', 'virtualMachine', 'id')
                if ($vm -and $nodes.Contains($vm)) { $target = $vm }
                & $addEdge $id $target 'route' "$prefix -> $hop"
            }
            elseif ($hop) {
                $risk = 'high'
                $reason = "No resource you can see has $hop. If none does, traffic to $prefix is dropped."
            }
            elseif ($hopType -eq 'Internet' -and $prefix -eq '0.0.0.0/0') {
                $risk = 'medium'
                $reason = 'All outbound traffic goes straight to the internet, around any firewall.'
            }
            elseif ($hopType -eq 'None') {
                $reason = "Traffic to $prefix is dropped on purpose (next hop: None)."
            }
            @{ name = [string](Get-Value $route 'name'); prefix = $prefix; nextHopType = $hopType; nextHop = $hop; target = $target; targetName = $(if ($target) { $nodes[$target].name } else { '' }); risk = $risk; reason = $reason }
        }
        $nodes[$id].routes = @($routes)
        $nodes[$id].propagation = if ([string](Get-Value $properties 'disableBgpRoutePropagation') -eq 'True') { 'off' } else { 'on' }
        $nodes[$id].risk = & $worst @($routes)
    }

    # NSG rules, each scored for what it opens to the internet.
    $anywhere = '^(\*|internet|any|0\.0\.0\.0/0|::/0)$'
    $sensitive = @{ 22 = 'SSH'; 3389 = 'RDP'; 5985 = 'WinRM'; 5986 = 'WinRM'; 23 = 'Telnet'; 21 = 'FTP'; 445 = 'SMB'; 1433 = 'SQL Server'; 3306 = 'MySQL'; 5432 = 'PostgreSQL'; 1521 = 'Oracle'; 27017 = 'MongoDB'; 6379 = 'Redis'; 9200 = 'Elasticsearch' }
    $values = {
        param($Properties, [string] $One, [string] $Many)
        @(@(Get-Value $Properties $One) + @(Get-Value $Properties $Many) | Where-Object { $null -ne $_ -and [string]$_ -ne '' } | ForEach-Object { [string]$_ })
    }
    $groupNames = {
        param($Properties, [string] $Key)
        @(@(Get-Value $Properties $Key) | ForEach-Object { $groupId = & $lower (Get-Value $_ 'id'); if ($groupId) { if ($nodes.Contains($groupId)) { $nodes[$groupId].name } else { ($groupId -split '/')[-1] } } })
    }
    foreach ($id in @($nodes.Keys)) {
        if ($nodes[$id].type -ne 'microsoft.network/networksecuritygroups') { continue }
        $properties = Get-Value $rows[$id].Row 'properties'
        $rules = foreach ($set in @(@('securityRules', $false), @('defaultSecurityRules', $true))) {
            foreach ($rule in @(Get-Value $properties $set[0])) {
                if ($null -eq $rule) { continue }
                $r = Get-Value $rule 'properties'
                $sources = @(& $values $r 'sourceAddressPrefix' 'sourceAddressPrefixes') + @(& $groupNames $r 'sourceApplicationSecurityGroups')
                $destinations = @(& $values $r 'destinationAddressPrefix' 'destinationAddressPrefixes') + @(& $groupNames $r 'destinationApplicationSecurityGroups')
                $ports = @(& $values $r 'destinationPortRange' 'destinationPortRanges')
                $direction = [string](Get-Value $r 'direction')
                $access = [string](Get-Value $r 'access')
                $risk = ''
                $reason = ''
                if (-not $set[1] -and $direction -eq 'Inbound' -and $access -eq 'Allow' -and @($sources | Where-Object { $_ -match $anywhere }).Count) {
                    # Which of the risky ports it opens, and how wide it is.
                    $open = [System.Collections.Generic.List[string]]::new()
                    $width = 0
                    foreach ($spec in $ports) {
                        if ($spec -eq '*') { $width = 65535; continue }
                        $low, $high = if ($spec -match '^(\d+)-(\d+)$') { [int]$Matches[1], [int]$Matches[2] } elseif ($spec -match '^\d+$') { [int]$spec, [int]$spec } else { 0, -1 }
                        $width += [Math]::Max(0, $high - $low + 1)
                        foreach ($port in @($sensitive.Keys | Sort-Object)) { if ($port -ge $low -and $port -le $high -and -not $open.Contains("$($sensitive[$port]) ($port)")) { $open.Add("$($sensitive[$port]) ($port)") } }
                    }
                    if ($ports -contains '*') { $risk = 'high'; $reason = 'Every port is open to the internet.' }
                    elseif ($open.Count) { $risk = 'high'; $reason = "$($open -join ', ') open to the internet." }
                    elseif ($width -gt 100) { $risk = 'medium'; $reason = "$('{0:N0}' -f $width) ports are open to the internet." }
                }
                @{
                    name = [string](Get-Value $rule 'name'); priority = [int](Get-Value $r 'priority'); direction = $direction; access = $access
                    protocol = [string](Get-Value $r 'protocol'); source = ($sources -join ', '); sourcePorts = ((& $values $r 'sourcePortRange' 'sourcePortRanges') -join ', ')
                    destination = ($destinations -join ', '); ports = ($ports -join ', '); isDefault = [bool]$set[1]; risk = $risk; reason = $reason
                }
            }
        }
        $nodes[$id].rules = @($rules | Sort-Object -Property { $_.direction }, { $_.isDefault }, { $_.priority })
        $nodes[$id].risk = & $worst @($rules)
    }

    $priority = @{ peering = 0; privatelink = 1; route = 2; dns = 3; network = 4; dependency = 5 }
    foreach ($candidate in @($candidates | Sort-Object -Property { $priority[$_.Kind] } -Stable)) {
        $pair = (@($candidate.From, $candidate.To) | Sort-Object) -join '|'
        if ($edges.Contains($pair)) {
            $edge = $edges[$pair]
            if ($edge.kind -eq $candidate.Kind -and $candidate.Label -and $edge.label -notlike "*$($candidate.Label)*") {
                $edge.label = (@($edge.label, $candidate.Label) | Where-Object { $_ }) -join '; '
            }
            continue
        }
        $edges[$pair] = @{ id = "e$($edges.Count + 1)"; source = $candidate.From; target = $candidate.To; kind = $candidate.Kind; label = $candidate.Label; view = '' }
    }

    # Peerings: the state, then what they let through.
    foreach ($edge in @($edges.Values)) {
        if ($edge.kind -ne 'peering') { continue }
        $pairKey = (@($edge.source, $edge.target) | Sort-Object) -join '|'
        $state = @(($edge.label -split '; ') | Where-Object { $_ } | Select-Object -Unique)
        $flags = if ($peeringFlags.Contains($pairKey)) { @('forwarded traffic', 'gateway transit', 'remote gateway' | Where-Object { $peeringFlags[$pairKey].Contains($_) }) } else { @() }
        $edge.label = (@($state) + @($flags)) -join ' · '
    }

    # NSGs and route tables as chips on what they are applied to; their links
    # to it are drawn only when they are shown as cards.
    $chipKinds = @{ 'microsoft.network/networksecuritygroups' = 'nsg'; 'microsoft.network/routetables' = 'udr' }
    foreach ($edge in @($edges.Values)) {
        if ($edge.kind -ne 'network') { continue }
        foreach ($end in @(@($edge.source, $edge.target), @($edge.target, $edge.source))) {
            $owner = $end[0]; $holder = $end[1]
            if (-not $nodes.Contains($owner) -or -not $chipKinds.Contains($nodes[$owner].type)) { continue }
            $isSubnet = $clusters.Contains($holder) -and $clusters[$holder].kind -eq 'subnet'
            $isNic = $nodes.Contains($holder) -and $nodes[$holder].type -eq 'microsoft.network/networkinterfaces'
            if (-not ($isSubnet -or $isNic)) { continue }
            $chip = @{ id = $owner; kind = $chipKinds[$nodes[$owner].type]; name = $nodes[$owner].name; risk = [string]$nodes[$owner].risk }
            $target = if ($isSubnet) { $clusters[$holder] } else { $nodes[$holder] }
            $target.chips = @($target.chips) + $chip
            $nodes[$owner].chip = $chip.kind
            $nodes[$owner].appliedTo = @(@($nodes[$owner].appliedTo) | Where-Object { $_ }) + $holder
            $edge.view = 'cards'
        }
    }
    # With chips, a route starts from the subnet it applies to.
    foreach ($edge in @($edges.Values)) {
        if ($edge.kind -ne 'route' -or -not $nodes.Contains($edge.source)) { continue }
        $table = $nodes[$edge.source]
        if (-not $table.chip) { continue }
        $edge.view = 'cards'
        foreach ($subnet in @($table.appliedTo | Where-Object { $clusters.Contains($_) })) {
            if ($edge.target -in @(& $ancestors $subnet) -or $subnet -in @(& $ancestors $edge.target)) { continue }
            $key = "chips|$subnet|$($edge.target)"
            $label = (@($edge.label -split '; ') | ForEach-Object { ($_ -split ' -> ')[0] }) -join ', '
            $label = "$label via $($table.name)"
            if ($edges.Contains($key)) { $edges[$key].label = "$($edges[$key].label); $label"; continue }
            $edges[$key] = @{ id = "e$($edges.Count + 1)"; source = $subnet; target = $edge.target; kind = 'route'; label = $label; view = 'chips' }
        }
    }

    # Subnet badges: what is on the subnet.
    foreach ($edge in @($edges.Values)) {
        foreach ($end in @(@($edge.source, $edge.target), @($edge.target, $edge.source))) {
            if ($clusters.Contains($end[0]) -and $clusters[$end[0]].kind -eq 'subnet' -and $nodes.Contains($end[1])) {
                $badge = switch ($nodes[$end[1]].type) { 'microsoft.network/networksecuritygroups' { 'NSG' } 'microsoft.network/routetables' { 'UDR' } 'microsoft.network/natgateways' { 'NAT' } }
                if ($badge) { $clusters[$end[0]].badges = @($clusters[$end[0]].badges) + "${badge}: $($nodes[$end[1]].name)" }
            }
        }
    }

    $nodeList = @($nodes.Values)
    @{
        Clusters = @($clusters.Values)
        Nodes    = $nodeList
        Edges    = @($edges.Values)
        Stats    = @{
            Resources   = @($nodeList | Where-Object { -not $_.external }).Count
            Outside     = @($nodeList | Where-Object { $_.external }).Count
            Connections = $edges.Count
            Orphans     = @($nodeList | Where-Object { $_.orphan }).Count
            Networks    = @($clusters.Values | Where-Object { $_.kind -eq 'vnet' }).Count
            Groups      = @($clusters.Values | Where-Object { $_.kind -eq 'resourcegroup' -and -not $_.external }).Count
            Flagged     = @($nodeList | Where-Object { $_.risk }).Count
        }
    }
}
