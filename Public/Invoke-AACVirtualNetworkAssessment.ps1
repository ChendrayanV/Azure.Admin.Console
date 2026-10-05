function Invoke-AACVirtualNetworkAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses virtual networks: address space and available IPs, every
        subnet, peerings, NSGs and application security groups, DNS, DDoS,
        flow logs, outbound access and gateways - with findings and what to
        do, a Spectre.Console view, objects, and CSV, PDF and interactive
        HTML reports.
    .DESCRIPTION
        Reads, with Azure Resource Graph - read-only, Reader is enough, no Az
        modules - the virtual networks and everything in or around them:
        network interfaces, route tables, NAT gateways, network security
        groups, application security groups, public IPs, private endpoints,
        private DNS zone links, DNS resolvers, VPN and ExpressRoute gateways,
        Azure Firewalls, Bastion hosts and Network Watcher flow logs.
        Without parameters it assesses every virtual network the account can
        see; -SubscriptionId, -ManagementGroupId, -ResourceGroupName and
        -Name narrow it.

        For each virtual network:
          Metadata      name, role (hub, spoke, peered, standalone), location,
                        resource group, subscription, tags, provisioning
                        state, flow timeout, BGP community
          Address space its prefixes; total IPs, IPs in subnets, unallocated
                        IPs; usable (Azure keeps 5 per subnet), used and
                        available IPs; the free CIDR blocks a new subnet can
                        take; overlaps with any other network you can see
          Subnets       prefix, usable / used / available IPs and % used,
                        purpose (gateway, firewall, Bastion, Route Server,
                        delegated, private endpoints, workloads), NSG, route
                        table and its default route, BGP propagation, NAT
                        gateway, the outbound path (NAT gateway, firewall or
                        NVA, forced tunnelling, public IPs, private subnet,
                        default outbound access), service endpoints and
                        policies, delegations, private endpoints and their
                        network policies, NICs, VMs, NICs with public IPs or
                        IP forwarding, flow logs
          Peerings      state, sync, remote network / subscription / region,
                        global, the allow* flags, gateway transit, remote
                        address space, subnet peering, reverse peering
          Security      DNS servers and private DNS zone links, DDoS
                        protection, virtual network encryption, flow logs,
                        Firewall and Bastion, private endpoints, ASGs (who
                        is in each, which rules name it) - and the NSGs on
                        its subnets, assessed rule by rule as
                        Get-AACNetworkSecurityGroup does

        Findings, each with a severity, the network and item, and what to do:
          High    a full subnet (or 95% used); a peering not Connected; an NSG
                  or a 0.0.0.0/0 route on GatewaySubnet; Bastion, Firewall or
                  Route Server subnets too small; an NSG rule open to the
                  internet on a management or database port
          Medium  a subnet 80% used; a peering out of sync; a subnet with
                  workloads and no NSG; VMs with public IPs; default outbound
                  access (being retired); public IPs without DDoS Network
                  Protection; no virtual network flow logs; private endpoints
                  whose privatelink zone isn't linked; private endpoint
                  connections not approved; a Basic VPN gateway; a
                  GatewaySubnet under /27
          Low     oversized or empty subnets; no free address space;
                  overlapping address spaces; encryption off; a single DNS
                  server; private endpoint network policies off; IP
                  forwarding with no route to it; empty or unused ASGs;
                  gateways that aren't zone-redundant
          Info    global peering (charged per GB); a remote network you
                  can't read; no Bastion where VMs have public IPs

        What you get depends on where the command runs:
          at the prompt    tiles, the networks with their IP capacity and
                           risk, the High and Medium findings, and - for up
                           to three networks - each in detail with its
                           subnets, peerings and free ranges, a page at a time
          piped onward     the AAC.VirtualNetwork objects (each with its
                           Subnets, Peerings, FreeRangeList,
                           PrivateEndpointList and Findings), with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only
        -CsvPath writes every subnet to CSV. -HtmlPath writes an interactive
        report - tiles, charts and tables of networks, subnets, peerings,
        free ranges, findings, private endpoints, ASGs and NSG rules, each
        collapsible and downloadable as CSV. -PdfPath writes a PDF with a
        section per network. With any of them, the console shows only the
        progress and the files written.
    .PARAMETER SubscriptionId
        Only the virtual networks in these subscriptions.
    .PARAMETER ManagementGroupId
        Only the virtual networks under these management groups.
    .PARAMETER ResourceGroupName
        Only the virtual networks in these resource groups.
    .PARAMETER Name
        Only these virtual networks; wildcards work, e.g. 'vnet-hub-*'.
    .PARAMETER CsvPath
        Write every subnet to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACVirtualNetworkAssessment
        Every virtual network the account can see, assessed.
    .EXAMPLE
        Invoke-AACVirtualNetworkAssessment -SubscriptionId 00000000-0000-0000-0000-000000000000 -Name 'vnet-hub-*', 'vnet-spoke-app'
        Some networks in detail: subnets, peerings, free ranges and findings.
    .EXAMPLE
        Invoke-AACVirtualNetworkAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\out\VNet.html -PdfPath .\out\VNet.pdf -CsvPath .\out\Subnets.csv
        A landing zone's networks as an interactive HTML report, a PDF and a CSV of every subnet.
    .EXAMPLE
        (Invoke-AACVirtualNetworkAssessment -NoDisplay).Subnets | Where-Object UsedPercent -GE 80 | Sort-Object UsedPercent -Descending
        The subnets running out of IPs.
    .EXAMPLE
        Invoke-AACVirtualNetworkAssessment -Name 'vnet-spoke-app' -NoDisplay | Select-Object -ExpandProperty FreeRangeList
        Where a new subnet fits.
    .OUTPUTS
        AAC.VirtualNetwork (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.VirtualNetwork')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Virtual network assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $PdfPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    # Read here, not inside the progress block (it runs in Invoke-AACProgress's scope).
    $request = @{
        SubscriptionId    = @($SubscriptionId | Where-Object { $_ })
        ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        GroupFilter       = $(if ($ResourceGroupName) { " | where resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' })
        Name              = @($Name | Where-Object { $_ })
        ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Title             = $Title
    }
    $at = {
        param($Value, [string[]] $Keys)
        foreach ($key in $Keys) { if ($Value -is [System.Collections.IDictionary]) { $Value = $Value[$key] } else { return $null } }
        $Value
    }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Virtual network assessment' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken

        # --- The networks in scope ----------------------------------------------------------------------------------
        Update-AACProgress -Id 'vnets' -Description 'Finding the virtual networks' -Indeterminate
        $scope = @{}
        if ($request.SubscriptionId.Count) { $scope['SubscriptionId'] = $request.SubscriptionId }
        if ($request.ManagementGroupId.Count) { $scope['ManagementGroupId'] = $request.ManagementGroupId }
        $found = Invoke-AACGraphBatch @scope -Query ([ordered]@{
                vnets = "resources | where type =~ 'microsoft.network/virtualnetworks'$($request.GroupFilter) | project id, name, resourceGroup, subscriptionId, location, tags, properties"
            })
        $vnets = @($found.Rows['vnets'] | Where-Object { $_ })
        if ($request.Name.Count) {
            $vnets = @($vnets | Where-Object { $vnetName = [string]$_['name']; @($request.Name | Where-Object { $vnetName -like $_ }).Count })
            $missing = @($request.Name | Where-Object { $pattern = $_; -not @($vnets | Where-Object { [string]$_['name'] -like $pattern }).Count })
            if ($missing.Count -eq $request.Name.Count) {
                $problem = [System.InvalidOperationException]::new("No virtual network named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found$(if ($request.SubscriptionId.Count -or $request.ManagementGroupId.Count -or $request.GroupFilter) { ' in that scope' } else { ' in any subscription you can see' }).")
                $problem.Data['AACHint'] = 'Wildcards work: -Name ''vnet-hub-*''.'
                throw $problem
            }
            foreach ($item in $missing) { Write-Warning "No virtual network named '$item' was found; it's left out." }
        }
        if (-not $vnets.Count) {
            $problem = [System.InvalidOperationException]::new('No virtual network was found in that scope.')
            $problem.Data['AACHint'] = 'Check the scope (-SubscriptionId, -ManagementGroupId, -ResourceGroupName) and that your account has Reader on it.'
            throw $problem
        }
        # The networks' subscriptions: their NICs, gateways, endpoints and NSGs are there.
        $subscriptions = @($vnets | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() } | Select-Object -Unique)
        Update-AACProgress -Id 'vnets' -Complete -Description ('{0:N0} virtual network(s) in {1:N0} subscription(s)' -f $vnets.Count, $subscriptions.Count)

        # --- What is in and around them -------------------------------------------------------------------------------
        $ipConfigurations = 'ipConfigurations = properties.ipConfigurations'
        $inScope = [ordered]@{
            nics             = "resources | where type =~ 'microsoft.network/networkinterfaces' | project id, name, resourceGroup, nsg = tolower(tostring(properties.networkSecurityGroup.id)), vm = tolower(tostring(properties.virtualMachine.id)), ipForwarding = tobool(properties.enableIPForwarding), privateEndpoint = tolower(tostring(properties.privateEndpoint.id)), ipConfigurations = properties.ipConfigurations"
            nsgs             = "resources | where type =~ 'microsoft.network/networksecuritygroups' | project id, name, resourceGroup, subscriptionId, location, tags, properties"
            routeTables      = "resources | where type =~ 'microsoft.network/routetables' | project id, name, resourceGroup, routes = properties.routes, disableBgpRoutePropagation = tobool(properties.disableBgpRoutePropagation)"
            natGateways      = "resources | where type =~ 'microsoft.network/natgateways' | project id, name, resourceGroup, zones, publicIpAddresses = properties.publicIpAddresses, publicIpPrefixes = properties.publicIpPrefixes"
            asgs             = "resources | where type =~ 'microsoft.network/applicationsecuritygroups' | project id, name, resourceGroup, location"
            publicIps        = "resources | where type =~ 'microsoft.network/publicipaddresses' | project id, name, ipAddress = tostring(properties.ipAddress), sku = tostring(sku.name), protectionMode = tostring(properties.ddosSettings.protectionMode), attachedTo = tolower(tostring(properties.ipConfiguration.id))"
            privateEndpoints = "resources | where type =~ 'microsoft.network/privateendpoints' | extend connection = coalesce(properties.privateLinkServiceConnections[0], properties.manualPrivateLinkServiceConnections[0]) | project id, name, resourceGroup, subnet = tolower(tostring(properties.subnet.id)), target = tostring(connection.properties.privateLinkServiceId), groupIds = connection.properties.groupIds, status = tostring(connection.properties.privateLinkServiceConnectionState.status)"
            flowLogs         = "resources | where type =~ 'microsoft.network/networkwatchers/flowlogs' | extend analytics = properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration | project id, name, target = tolower(tostring(properties.targetResourceId)), enabled = tobool(properties.enabled), retentionEnabled = tobool(properties.retentionPolicy.enabled), retentionDays = toint(properties.retentionPolicy.days), storageId = tostring(properties.storageId), analytics = tobool(analytics.enabled), workspace = tostring(analytics.workspaceResourceId), interval = toint(analytics.trafficAnalyticsInterval), version = toint(properties.format.version)"
            gateways         = "resources | where type =~ 'microsoft.network/virtualnetworkgateways' | project id, name, resourceGroup, gatewayType = tostring(properties.gatewayType), vpnType = tostring(properties.vpnType), sku = tostring(properties.sku.name), activeActive = tobool(properties.activeActive), enableBgp = tobool(properties.enableBgp), $ipConfigurations"
            firewalls        = "resources | where type =~ 'microsoft.network/azurefirewalls' | project id, name, resourceGroup, tier = tostring(properties.sku.tier), zones, threatIntelMode = tostring(properties.threatIntelMode), $ipConfigurations"
            bastions         = "resources | where type =~ 'microsoft.network/bastionhosts' | project id, name, resourceGroup, sku = tostring(sku.name), $ipConfigurations"
            dnsResolvers     = "resources | where type =~ 'microsoft.network/dnsresolvers' | project id, name, resourceGroup, vnet = tolower(tostring(properties.virtualNetwork.id))"
        }
        # Every network and private DNS zone link the account can see: remote
        # peerings, overlapping address spaces, zones linked from a hub.
        $everywhere = [ordered]@{
            subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
            allVnets      = "resources | where type =~ 'microsoft.network/virtualnetworks' | project id, name, subscriptionId, location, prefixes = properties.addressSpace.addressPrefixes, peerings = properties.virtualNetworkPeerings"
            dnsLinks      = "resources | where type =~ 'microsoft.network/privatednszones/virtualnetworklinks' | project id, zone = tolower(tostring(split(id, '/')[8])), vnet = tolower(tostring(properties.virtualNetwork.id)), registration = tobool(properties.registrationEnabled), state = tostring(properties.virtualNetworkLinkState)"
        }
        $total = $inScope.Count + $everywhere.Count
        Update-AACProgress -Id 'read' -Total $total -Description 'Reading NICs, route tables, NSGs, ASGs, endpoints, gateways and flow logs'
        $onProgress = { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name" }
        $scoped = Invoke-AACGraphBatch -SubscriptionId $subscriptions -Query $inScope -AllowFailure @($inScope.Keys) -OnProgress $onProgress
        $shared = Invoke-AACGraphBatch -Query $everywhere -AllowFailure @($everywhere.Keys) -OnProgress $onProgress
        $rows = { param([string] $Key) @(if ($scoped.Rows.Contains($Key)) { $scoped.Rows[$Key] } elseif ($shared.Rows.Contains($Key)) { $shared.Rows[$Key] }) | Where-Object { $_ } }
        $failed = @(@($scoped.Errors.Keys) + @($shared.Errors.Keys) | Where-Object { $_ })
        foreach ($key in $failed) { Write-Warning "The $key couldn't be read - the assessment carries on without them: $(if ($scoped.Errors.Contains($key)) { $scoped.Errors[$key] } else { $shared.Errors[$key] })" }
        Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} NIC(s), {1:N0} NSG(s), {2:N0} route table(s), {3:N0} private endpoint(s), {4:N0} network(s) to compare with' -f @(& $rows 'nics').Count, @(& $rows 'nsgs').Count, @(& $rows 'routeTables').Count, @(& $rows 'privateEndpoints').Count, @(& $rows 'allVnets').Count)

        # Each network's peerings as the remote network IDs (reverse peering).
        $allNetworks = @(foreach ($row in & $rows 'allVnets') {
                @{ id = [string]$row['id']; name = [string]$row['name']; subscriptionId = [string]$row['subscriptionId']; location = [string]$row['location']; prefixes = @($row['prefixes'] | Where-Object { $_ })
                    peers = @(@($row['peerings']) | Where-Object { $_ } | ForEach-Object { ([string](& $at $_ 'properties', 'remoteVirtualNetwork', 'id')).ToLowerInvariant() }) }
            })
        $subscriptionNames = @{}
        foreach ($row in & $rows 'subscriptions') { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }

        # --- The NSGs on these networks, assessed as Get-AACNetworkSecurityGroup does ------------------------------
        Update-AACProgress -Id 'assess' -Description 'Assessing the subnets, peerings, NSGs and security' -Indeterminate
        $vnetIds = @{}
        foreach ($vnet in $vnets) { $vnetIds[([string]$vnet['id']).ToLowerInvariant()] = $true }
        $subnetRows = @(foreach ($vnet in $vnets) {
                foreach ($subnet in @(& $at $vnet 'properties', 'subnets') | Where-Object { $_ }) {
                    $sp = & $at $subnet 'properties'
                    @{
                        subnetId = ([string]$subnet['id']).ToLowerInvariant(); name = [string]$subnet['name']; vnetId = ([string]$vnet['id']).ToLowerInvariant(); vnetName = [string]$vnet['name']
                        prefix = [string]$(if (& $at $sp 'addressPrefix') { & $at $sp 'addressPrefix' } else { @(& $at $sp 'addressPrefixes')[0] })
                        nsg = ([string](& $at $sp 'networkSecurityGroup', 'id')).ToLowerInvariant()
                    }
                }
            })
        $nics = @(& $rows 'nics' | Where-Object {
                @(@($_['ipConfigurations']) | Where-Object { $_ } | Where-Object { ([string](& $at $_ 'properties', 'subnet', 'id')) -match '^(.+/virtualnetworks/[^/]+)/subnets/' -and $vnetIds.Contains($Matches[1].ToLowerInvariant()) }).Count
            })
        $nsgNics = @(foreach ($nic in $nics) {
                $configurations = @($nic['ipConfigurations'] | Where-Object { $_ })
                @{
                    id = [string]$nic['id']; name = [string]$nic['name']; resourceGroup = [string]$nic['resourceGroup']; nsg = [string]$nic['nsg']; vm = [string]$nic['vm']
                    subnet = $(if ($configurations) { [string](& $at $configurations[0] 'properties', 'subnet', 'id') } else { '' })
                    ips = @($configurations | ForEach-Object { [string](& $at $_ 'properties', 'privateIPAddress') } | Where-Object { $_ })
                    asgs = @($configurations | ForEach-Object { @(& $at $_ 'properties', 'applicationSecurityGroups') } | Where-Object { $_ } | ForEach-Object { [string](& $at $_ 'id') })
                }
            })
        $applied = @{}
        foreach ($id in @($subnetRows | ForEach-Object { $_.nsg }) + @($nsgNics | ForEach-Object { $_.nsg })) { if ($id) { $applied[$id.ToLowerInvariant()] = $true } }
        $nsgs = @(& $rows 'nsgs' | Where-Object { $applied.Contains(([string]$_['id']).ToLowerInvariant()) })
        $nsgAssessment = ConvertTo-AACNsgAssessment -NetworkSecurityGroup $nsgs -NetworkInterface $nsgNics -Subnet $subnetRows -FlowLog @(& $rows 'flowLogs') -Diagnostic $null -SubscriptionName $subscriptionNames

        $assessment = ConvertTo-AACVirtualNetworkAssessment -VirtualNetwork $vnets -AllNetwork $allNetworks -NetworkInterface $nics `
            -RouteTable @(& $rows 'routeTables') -NatGateway @(& $rows 'natGateways') -ApplicationSecurityGroup @(& $rows 'asgs') -PublicIp @(& $rows 'publicIps') `
            -PrivateEndpoint @(& $rows 'privateEndpoints') -FlowLog @(& $rows 'flowLogs') -Firewall @(& $rows 'firewalls') -Bastion @(& $rows 'bastions') `
            -Gateway @(& $rows 'gateways') -DnsLink @(& $rows 'dnsLinks') -DnsResolver @(& $rows 'dnsResolvers') -NetworkSecurityGroup $nsgs `
            -NsgAssessment $nsgAssessment -SubscriptionName $subscriptionNames
        $assessment['Failed'] = $failed
        $stats = $assessment.Stats
        Update-AACProgress -Id 'assess' -Complete -Description ('Assessed {0:N0} network(s), {1:N0} subnet(s), {2:N0} peering(s), {3:N0} NSG(s): {4} high, {5} medium, {6} low finding(s)' -f $stats.VirtualNetworks, $stats.Subnets, $stats.Peerings, $nsgs.Count, $stats.High, $stats.Medium, $stats.Low)

        $detail = [ordered]@{
            Scope = if ($request.ManagementGroupId.Count) { "management group(s) $($request.ManagementGroupId -join ', ')" } elseif ($request.SubscriptionId.Count) { "subscription(s) $($request.SubscriptionId -join ', ')" } else { 'every subscription the account can see' }
        }
        if ($request.GroupFilter) { $detail['Resource groups'] = $request.ResourceGroupName -join ', ' }
        if ($request.Name.Count) { $detail['Virtual networks'] = $request.Name -join ', ' }
        $csvRows = @($assessment.Subnets | Select-Object -Property VirtualNetwork, Subnet, Purpose, Prefix, Size, Usable, Used, Available, UsedPercent, Nsg, RouteTable, DefaultRoute, NatGateway, Outbound, DefaultOutboundAccess, ServiceEndpoints, Delegations, PrivateEndpoints, PrivateEndpointPolicies, Nics, Vms, PublicIpNics, FlowLogs, SubscriptionName, ResourceGroup, SubnetId)
        $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $csvRows -Noun 'subnet' -PdfPath $pdfFullPath -WritePdf {
            Write-AACVirtualNetworkPdf -Assessment $assessment -Path $pdfFullPath -Title $request.Title -Detail $detail
        } -HtmlPath $htmlFullPath -WriteHtml {
            Write-AACVirtualNetworkHtml -Assessment $assessment -Path $htmlFullPath -Title $request.Title -Detail $detail
        }
        @{ Assessment = $assessment; Scope = $detail }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACVirtualNetworkView -Assessment $state.Assessment -Scope $state.Scope
        }
    }
    if ($returnObjects) {
        $state.Assessment.VirtualNetworks
    }
}
