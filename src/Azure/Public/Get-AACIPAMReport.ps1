function Get-AACIPAMReport {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        IP address management without a server: Azure's address space
        measured against your address plan - spaces and blocks, every
        network, subnet and private IP address, overlaps, free space and the
        next ranges to hand out - as a Spectre.Console view, objects, and
        CSV, PDF and a tabbed, interactive HTML report.
    .DESCRIPTION
        Read-only, from Azure Resource Graph (Reader is enough, no Az
        modules, nothing to deploy): virtual networks with their subnets,
        peerings and DNS servers, Virtual WAN hubs, network interfaces, scale
        set instances, load balancers, firewalls, Bastion, gateways,
        application gateways, Private Link services, private endpoints and
        public IPs. Nothing is stored: every run is worked out afresh from
        Azure, so it can't drift from what is deployed.

        The address plan (-AddressPlan) is what Azure is measured against:
        spaces (an organisation, a region, an environment) holding blocks
        (the ranges handed out to Azure), plus external ranges - on-premises
        or partner networks - that Azure must not overlap. Without one, the
        private ranges are the plan: RFC 1918 (10/8, 172.16/12, 192.168/16)
        and RFC 6598 shared space (100.64/10).

        The report:
          Spaces          each space's blocks, size, allocated and free
                          addresses, networks, subnets, addresses in use
          Blocks          each block's networks, address space allocated (the
                          union of the network and external prefixes in it),
                          free space, its largest free range, the next free
                          range of the first -NextAvailable size and how many
                          still fit, and its status: Warning at
                          -WarningPercent, Critical at -CriticalPercent, Full
          Networks        virtual networks, Virtual WAN hubs and external
                          ranges: Managed (every IPv4 prefix in a block),
                          Partly managed or Unmanaged; prefixes, subnets,
                          addresses used and free, address space in no subnet,
                          DNS servers (or Azure-provided), peerings, overlaps,
                          the Azure IPAM reservation tag (X-IPAM-RES-ID)
          Subnets         prefix, address range and usable range (Azure keeps
                          the first four addresses and the last), usable /
                          used / available, purpose (gateway, firewall,
                          Bastion, delegated, private endpoints, workloads)
                          and what takes the addresses
          IP addresses    every address Azure lists in a subnet - virtual
                          machines, scale set instances, private endpoints,
                          load balancer frontends, firewalls, gateways,
                          Bastion, application gateways, unattached network
                          interfaces - with its allocation (static, dynamic),
                          public IP and what it belongs to; a subnet's count
                          and its list always agree
          Overlaps        every pair of address spaces that overlap: High when
                          the networks are peered (traffic can't route),
                          Medium with an external range or a hub, Low otherwise
          Free space      every free range of every block; the next ranges of
                          each -NextAvailable size: the best fit (the smallest
                          free range it fits, so larger ranges stay whole) and
                          the lowest free address
          CIDR check      each -TestCidr: free, taken or partly taken, and by
                          what
          Findings        full and filling blocks and subnets, overlaps,
                          networks outside (or straddling) the plan, networks
                          spanning blocks, a reservation tag on an unplanned
                          network, unattached interfaces holding addresses,
                          unused blocks

        The HTML report has a tab for each, a tree of the plan (space >
        block > network > subnet) on its Summary tab, a Space selector that
        filters every tab, and a card that follows the pointer over a row
        with its details (click the row for every field).

        What you get depends on where the command runs:
          at the prompt    tiles and the main tables, a page at a time
          piped onward     the -View rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the -View rows; -HtmlPath and -PdfPath the reports;
        -Open opens the HTML report (in a temporary file without -HtmlPath).
    .PARAMETER AddressPlan
        The address plan: the path of a .psd1, .json or .csv file, or a
        hashtable.

        As a .psd1 or .json file, or a hashtable:
          @{ Spaces = @(
                 @{ Name = 'Corp'; Description = '...'; Blocks = @(
                     @{ Name = 'Azure-EU'; Cidr = '10.20.0.0/14' }
                     @{ Name = 'Azure-US'; Cidr = '10.24.0.0/14' } ) } )
             External = @( @{ Name = 'London DC'; Cidr = '10.0.0.0/16' } ) }

        As a .csv file: one row per range - Space, Block, Cidr, Kind (Block, or
        External: then Block is its name), Description.

        Blocks of one space must not overlap; blocks of different spaces
        may (a network then counts in both).
    .PARAMETER SubscriptionId
        Only the networks in these subscriptions.
    .PARAMETER ManagementGroupId
        Only the networks in the subscriptions under these management
        groups.
    .PARAMETER NextAvailable
        The prefix lengths to find free ranges for (24 if not given; 8 to
        29): -NextAvailable 24, 22 lists the next /24 and /22 of every block.
        The first is the one the Blocks tab shows.
    .PARAMETER TestCidr
        Ranges to check: free, taken or partly taken, and by what. The
        objects returned are then these checks (unless -View says else).
    .PARAMETER WarningPercent
        A block or subnet this full (in %) is flagged Warning (80 if not
        given).
    .PARAMETER CriticalPercent
        A block or subnet this full (in %) is flagged Critical (90 if not
        given).
    .PARAMETER View
        What is returned and written to -CsvPath: Block (default), Space,
        Network, Subnet, IpAddress, Overlap, FreeRange, NextAvailable,
        CidrCheck or Finding.
    .PARAMETER CsvPath
        Write the -View rows to this CSV file.
    .PARAMETER HtmlPath
        Write the tabbed, interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Open
        Open the HTML report when it is written - in a temporary file when
        -HtmlPath isn't given.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Get-AACIPAMReport -Open
        Every network you can see against the private ranges, in your browser.
    .EXAMPLE
        Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -HtmlPath .\IPAM.html -PdfPath .\IPAM.pdf
        Your plan's spaces and blocks: what is allocated, free, overlapping, and what to hand out next.
    .EXAMPLE
        Get-AACIPAMReport -AddressPlan .\ipam-plan.psd1 -NextAvailable 24, 22 -View NextAvailable -NoDisplay | Where-Object Fit -EQ 'Best fit'
        The next /24 and /22 of every block, for a new network.
    .EXAMPLE
        Get-AACIPAMReport -TestCidr 10.20.8.0/22, 10.21.0.0/16
        Are these ranges free? If not, which networks have them.
    .EXAMPLE
        Get-AACIPAMReport -ManagementGroupId 'mg-landingzones' -View IpAddress -CsvPath .\ips.csv
        Every private IP address of a landing zone, to feed another IPAM or CMDB.
    .OUTPUTS
        AAC.IpamBlock, AAC.IpamSpace, AAC.IpamNetwork, AAC.IpamSubnet, AAC.IpamIpAddress, AAC.IpamOverlap, AAC.IpamFreeRange, AAC.IpamNextAvailable, AAC.IpamCidrCheck or AAC.IpamFinding, by -View (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.IpamBlock', 'AAC.IpamSpace', 'AAC.IpamNetwork', 'AAC.IpamSubnet', 'AAC.IpamIpAddress', 'AAC.IpamOverlap', 'AAC.IpamFreeRange', 'AAC.IpamNextAvailable', 'AAC.IpamCidrCheck', 'AAC.IpamFinding')]
    param(
        [object] $AddressPlan,

        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateRange(8, 29)]
        [int[]] $NextAvailable = @(24),

        [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$')]
        [string[]] $TestCidr,

        [ValidateRange(1, 100)]
        [int] $WarningPercent = 80,

        [ValidateRange(1, 100)]
        [int] $CriticalPercent = 90,

        [ValidateSet('Block', 'Space', 'Network', 'Subnet', 'IpAddress', 'Overlap', 'FreeRange', 'NextAvailable', 'CidrCheck', 'Finding')]
        [string] $View = 'Block',

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [switch] $Open,

        [string] $Title = 'IP address management report',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if ($WarningPercent -gt $CriticalPercent) { throw "Azure Admin Console needs -WarningPercent ($WarningPercent) at or below -CriticalPercent ($CriticalPercent)." }
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    # A CIDR check is the question asked: it is what comes back, unless -View says otherwise.
    if ($TestCidr -and -not $PSBoundParameters.ContainsKey('View')) { $View = 'CidrCheck' }
    $planInput = if ($AddressPlan -is [string]) { & $resolve $AddressPlan } else { $AddressPlan }
    $plan = Read-AACIpamPlan -Plan $planInput
    $htmlFullPath = & $resolve $HtmlPath
    if ($Open -and -not $htmlFullPath) { $htmlFullPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('AAC-IPAM-{0:yyyyMMdd-HHmmss}.html' -f [datetime]::Now) }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ })
        NextAvailable = @($NextAvailable); TestCidr = @($TestCidr | Where-Object { $_ }); Warning = $WarningPercent; Critical = $CriticalPercent
    }

    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: IP address management' -Color 'deepskyblue3_1' }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        Update-AACProgress -Id 'networks' -Description 'Finding the virtual networks and Virtual WAN hubs' -Indeterminate
        $scope = @{}
        if ($request.SubscriptionId.Count) { $scope['SubscriptionId'] = $request.SubscriptionId }
        if ($request.ManagementGroupId.Count) { $scope['ManagementGroupId'] = $request.ManagementGroupId }
        $found = Invoke-AACGraphBatch @scope -Query ([ordered]@{
                vnets = "resources | where type =~ 'microsoft.network/virtualnetworks' | project id, name, resourceGroup, subscriptionId, location, tags, prefixes = properties.addressSpace.addressPrefixes, dnsServers = properties.dhcpOptions.dnsServers, subnets = properties.subnets, peerings = properties.virtualNetworkPeerings"
                hubs  = "resources | where type =~ 'microsoft.network/virtualhubs' | where isempty(kind) | project id, name, resourceGroup, subscriptionId, location, prefix = tostring(properties.addressPrefix), vwan = tostring(properties.virtualWan.id)"
            }) -AllowFailure @('hubs')
        $vnets = @($found.Rows['vnets'] | Where-Object { $_ })
        $hubs = @($found.Rows['hubs'] | Where-Object { $_ })
        $notices = [System.Collections.Generic.List[string]]::new()
        if ($found.Errors.Contains('hubs')) { $notices.Add("Virtual WAN hubs couldn't be read: $($found.Errors['hubs'])") }
        $subscriptions = @(@($vnets) + @($hubs) | ForEach-Object { ([string]$_['subscriptionId']).ToLowerInvariant() } | Select-Object -Unique)
        Update-AACProgress -Id 'networks' -Complete -Description ('{0:N0} virtual network(s) and {1:N0} hub(s) in {2:N0} subscription(s)' -f $vnets.Count, $hubs.Count, $subscriptions.Count)

        # What takes addresses from the subnets, in those subscriptions; subscription names from everywhere.
        $configsOf = { param([string] $Name) "iff(isnull(properties.$Name), dynamic([]), properties.$Name)" }
        $inScope = [ordered]@{
            nics             = "resources | where type =~ 'microsoft.network/networkinterfaces' | project id, name, resourceGroup, subscriptionId, vm = tostring(properties.virtualMachine.id), privateEndpoint = tostring(properties.privateEndpoint.id), managedBy = tostring(managedBy), ipConfigurations = properties.ipConfigurations"
            scaleSetNics     = "computeresources | where type =~ 'microsoft.compute/virtualmachinescalesets/virtualmachines/networkinterfaces' | project id, resourceGroup, subscriptionId, ipConfigurations = properties.ipConfigurations"
            ipResources      = "resources | where type in~ ('microsoft.network/loadbalancers', 'microsoft.network/azurefirewalls', 'microsoft.network/bastionhosts', 'microsoft.network/virtualnetworkgateways', 'microsoft.network/applicationgateways', 'microsoft.network/privatelinkservices') | project id, name, type, resourceGroup, subscriptionId, configs = array_concat($(& $configsOf 'ipConfigurations'), $(& $configsOf 'frontendIPConfigurations'), $(& $configsOf 'gatewayIPConfigurations'))"
            privateEndpoints = "resources | where type =~ 'microsoft.network/privateendpoints' | extend c = coalesce(properties.privateLinkServiceConnections[0], properties.manualPrivateLinkServiceConnections[0]) | project id, name, target = tostring(c.properties.privateLinkServiceId)"
            publicIps        = "resources | where type =~ 'microsoft.network/publicipaddresses' | project id, ipAddress = tostring(properties.ipAddress)"
        }
        $rowsOf = @{}
        if ($subscriptions.Count) {
            Update-AACProgress -Id 'read' -Total ($inScope.Count + 1) -Description 'Reading network interfaces, scale sets, load balancers, gateways and endpoints'
            $onProgress = { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name" }
            $scoped = Invoke-AACGraphBatch -SubscriptionId $subscriptions -Query $inScope -AllowFailure @($inScope.Keys) -OnProgress $onProgress
            $shared = Invoke-AACGraphBatch -Query ([ordered]@{ subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name" }) -AllowFailure @('subscriptions') -OnProgress $onProgress
            foreach ($key in @($scoped.Rows.Keys)) { $rowsOf[$key] = @($scoped.Rows[$key] | Where-Object { $_ }) }
            $rowsOf['subscriptions'] = @($shared.Rows['subscriptions'] | Where-Object { $_ })
            foreach ($key in @(@($scoped.Errors.Keys) + @($shared.Errors.Keys) | Where-Object { $_ })) {
                $why = if ($scoped.Errors.Contains($key)) { $scoped.Errors[$key] } else { $shared.Errors[$key] }
                $notices.Add("The $key couldn't be read - their addresses are listed from their IDs only: $why")
            }
            Update-AACProgress -Id 'read' -Complete -Description ('Read {0:N0} NIC(s), {1:N0} scale set NIC(s), {2:N0} other resource(s)' -f @($rowsOf['nics']).Count, @($rowsOf['scaleSetNics']).Count, @($rowsOf['ipResources']).Count)
        }
        $names = @{}
        foreach ($row in @($rowsOf['subscriptions'])) { if ($row) { $names[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] } }

        Update-AACProgress -Id 'plan' -Description 'Measuring the networks against the address plan' -Indeterminate
        $ipam = ConvertTo-AACIpamReport -Plan $plan -VirtualNetwork $vnets -Hub $hubs -NetworkInterface @($rowsOf['nics']) -ScaleSetInterface @($rowsOf['scaleSetNics']) `
            -IpResource @($rowsOf['ipResources']) -PrivateEndpoint @($rowsOf['privateEndpoints']) -PublicIp @($rowsOf['publicIps']) -SubscriptionName $names `
            -NextAvailable $request.NextAvailable -TestCidr $request.TestCidr -WarningPercent $request.Warning -CriticalPercent $request.Critical
        $s = $ipam.Stats
        Update-AACProgress -Id 'plan' -Complete -Description ('{0:N0} block(s), {1:N0} network(s), {3:N0} IP(s), {4} overlap(s), {5} high' -f $s.Blocks, $s.Networks, $s.Subnets, $s.IpAddresses, $s.Overlaps, $s.High)
        @{ Ipam = $ipam; Notices = $notices.ToArray() }
    }

    # --- Report ---------------------------------------------------------------------------------------------------
    $r = $state.Ipam
    $s = $r.Stats
    $rank = Get-AACSeverityRank
    $statusTones = @{ Full = 'bad'; Critical = 'bad'; Warning = 'warn'; OK = 'good'; Unused = 'neutral'; Empty = 'neutral'; 'IPv6 only' = 'neutral' }
    $managedTones = @{ Managed = 'good'; 'Partly managed' = 'warn'; Unmanaged = 'bad'; 'IPv6 only' = 'neutral' }
    $kindTones = @{ 'Virtual network' = 'info'; 'Virtual WAN hub' = 'violet'; External = 'neutral' }
    $checkTones = @{ Free = 'good'; 'Free, outside every block' = 'warn'; 'Partly taken' = 'warn'; Taken = 'bad' }
    $fitTones = @{ 'Best fit' = 'good'; 'Lowest address' = 'info'; 'No room' = 'bad' }
    $percentTip = "Warning at $WarningPercent%, Critical at $CriticalPercent%"
    $planText = if ($plan.Default) { 'the private ranges (RFC 1918, RFC 6598)' } else { $plan.Source }
    $next = "/$($s.NextSize)"
    $multiSpace = @($r.Spaces).Count -gt 1
    $notices = @(@(if ($plan.Default) { @{ Status = 'Info'; Text = 'No -AddressPlan: networks are measured against the private ranges (RFC 1918 and RFC 6598). Give your spaces and blocks with -AddressPlan for a plan of your own.' } }) + @($state.Notices | ForEach-Object { @{ Status = 'Warning'; Text = $_ } }))
    $report = @{
        Subtitle = "Address plan: $planText"
        Scope    = @{ Key = 'Space'; Label = 'Space'; Values = @($r.Spaces | ForEach-Object { $_.Space }); Card = 'spaces'; Note = 'Choose a space to see only its blocks, networks, subnets and addresses.' }
        Facts    = [ordered]@{
            'Address plan' = $planText
            Scope          = $(if ($ManagementGroupId) { "management group(s) $($ManagementGroupId -join ', ')" } elseif ($SubscriptionId) { "subscription(s) $($SubscriptionId -join ', ')" } else { 'every subscription the account can see' })
            Thresholds     = $percentTip
            'Next ranges'  = (@($NextAvailable | Sort-Object -Unique | ForEach-Object { "/$_" }) -join ', ')
            Generated      = "$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)) UTC"
        }
        Status   = $(if ($s.High) { 'Failed' } elseif ($s.Medium) { 'Warning' } else { 'Success' })
        Headline = "$($s.Blocks) block(s) in $($s.Spaces) space(s), $($s.AllocatedPercent)% allocated; $($s.Managed) of $($s.Networks) network(s) in the plan; $('{0:N0}' -f $s.IpAddresses) IP address(es) in use; $($s.Overlaps) overlap(s); $('{0:N0}' -f $s.Fits) free $next range(s)"
        Tiles    = @(
            @{ Value = '{0:N0}' -f $s.Blocks; Label = "blocks in $($s.Spaces) space(s)"; Tone = 'info'; Table = 'blocks' }
            @{ Value = $(if ($null -ne $s.AllocatedPercent) { '{0:N1}%' -f $s.AllocatedPercent } else { '-' }); Label = 'of the plan allocated'; Tone = $(if ($s.AllocatedPercent -ge $CriticalPercent) { 'bad' } elseif ($s.AllocatedPercent -ge $WarningPercent) { 'warn' } else { 'good' }); Table = 'blocks' }
            @{ Value = "$($s.Managed)/$($s.Networks)"; Label = 'networks in the plan'; Tone = $(if ($s.Unmanaged + $s.PartlyManaged) { 'warn' } else { 'good' }); Table = 'networks' }
            @{ Value = '{0:N0}' -f ($s.Unmanaged + $s.PartlyManaged); Label = 'outside (or straddling) it'; Tone = $(if ($s.Unmanaged + $s.PartlyManaged) { 'bad' } else { 'good' }); Table = 'networks'; Filters = @{ Status = 'Unmanaged' } }
            @{ Value = '{0:N0}' -f $s.IpAddresses; Label = 'IP addresses in use'; Tone = 'info'; Table = 'ipaddresses' }
            @{ Value = '{0:N0}' -f $s.Fits; Label = "free $next ranges"; Tone = $(if ($s.Fits) { 'good' } else { 'bad' }); Table = 'next' }
            @{ Value = '{0:N0}' -f $s.Overlaps; Label = "overlaps ($($s.PeeredOverlaps) peered)"; Tone = $(if ($s.PeeredOverlaps) { 'bad' } elseif ($s.Overlaps) { 'warn' } else { 'good' }); Table = 'overlaps' }
            @{ Value = '{0:N0}' -f $s.FullSubnets; Label = 'subnets full or critical'; Tone = $(if ($s.FullSubnets) { 'bad' } else { 'good' }); Table = 'subnets' }
            @{ Value = '{0:N0}' -f $s.High; Label = 'high findings'; Tone = $(if ($s.High) { 'bad' } else { 'good' }); Table = 'findings'; Filters = @{ Severity = 'High' } }
        )
        Notices  = $notices
        Tree     = $r.Tree
        Charts   = @(
            @{ Title = 'Blocks - % allocated'; Items = @($r.Blocks | Select-Object -First 15 | ForEach-Object { @{ Label = $(if ($multiSpace) { "$($_.Space) / $($_.Block)" } else { $_.Block }); Value = [double]$_.AllocatedPercent; Display = "$($_.AllocatedPercent)% of $($_.Cidr)"; Tone = $statusTones[$_.Status]; Filter = $_.Block } }); Table = 'blocks'; Column = 'Block'; Format = 'N1'; Console = $true }
            @{ Title = 'Networks by status'; Kind = 'donut'; CenterLabel = 'networks'; Items = @(foreach ($k in 'Managed', 'Partly managed', 'Unmanaged') { $n = @($r.Networks | Where-Object { $_.Kind -ne 'External' -and $_.Status -eq $k }).Count; if ($n) { @{ Label = $k; Value = $n; Tone = $managedTones[$k]; Filter = $k } } }); Table = 'networks'; Column = 'Status' }
            @{ Title = 'IP addresses by kind'; Kind = 'donut'; CenterLabel = 'addresses'; Items = @($r.IpAddresses | Group-Object -Property Kind | Sort-Object -Property Count -Descending | Select-Object -First 8 | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'ipaddresses'; Column = 'Kind' }
            @{ Title = 'Fullest subnets (% of usable addresses)'; Items = @($r.Subnets | Where-Object { $null -ne $_.UsedPercent } | Sort-Object -Property UsedPercent -Descending | Select-Object -First 12 | ForEach-Object { @{ Label = "$($_.Network) / $($_.Subnet)"; Value = [double]$_.UsedPercent; Display = "$($_.UsedPercent)% ($($_.Used) of $($_.Usable))"; Tone = $statusTones[$_.Status]; Filter = $_.Subnet } }); Table = 'subnets'; Column = 'Subnet'; Format = 'N1' }
            @{ Title = 'Findings by category'; Kind = 'donut'; CenterLabel = 'findings'; Items = @($r.Findings | Group-Object -Property Category | ForEach-Object { @{ Label = $_.Name; Value = $_.Count; Filter = $_.Name } }); Table = 'findings'; Column = 'Category' }
        )
        Tabs     = @(
            @{ Name = 'Spaces'; Badge = @($r.Spaces).Count; Tone = 'violet'; Note = "Each space of the plan ($planText): its blocks, how much is allocated and free, its networks, subnets and addresses in use. Choose a space above to see only its rows in every tab." }
            @{ Name = 'Blocks'; Badge = @($r.Blocks).Count; Tone = $(if (@($r.Blocks | Where-Object { $_.Status -in 'Full', 'Critical' }).Count) { 'bad' } else { 'info' }); Note = "Each block: the networks in it, the address space they take (overlaps counted once), free space, its largest free range and the next free $next ($percentTip). Hover a row for its free ranges and networks." }
            @{ Name = 'Networks'; Badge = @($r.Networks).Count; Tone = $(if ($s.Unmanaged + $s.PartlyManaged) { 'warn' } else { 'good' }); Note = 'Virtual networks, Virtual WAN hubs and external ranges: in the plan (Managed), partly, or outside it - with their subnets, addresses used, DNS servers, peerings and overlaps.' }
            @{ Name = 'Subnets'; Badge = @($r.Subnets).Count; Tone = $(if ($s.FullSubnets) { 'bad' } else { 'info' }); Note = "Every subnet: its range, usable range (Azure keeps the first four addresses and the last), usable / used / available addresses and what takes them ($percentTip)." }
            @{ Name = 'IP addresses'; Badge = @($r.IpAddresses).Count; Tone = 'info'; Note = 'Every address Azure lists in a subnet - virtual machines, scale set instances, private endpoints, load balancers, gateways, firewalls, unattached network interfaces - so the count and the list always agree.' }
            @{ Name = 'Overlaps'; Badge = @($r.Overlaps).Count; Tone = $(if ($s.PeeredOverlaps) { 'bad' } elseif ($s.Overlaps) { 'warn' } else { 'good' }); Note = 'Every pair of address spaces that overlap: High when peered (traffic can''t route), Medium with an external range or a hub, Low when isolated (they can never be peered).' }
            @{ Name = 'Free space'; Badge = @($r.NextAvailable | Where-Object { $_.Candidate }).Count; Tone = 'good'; Note = 'The next ranges to hand out - the best fit (the smallest free range it fits, keeping larger ranges whole) and the lowest free address - then every free range of every block.' }
            @{ Name = 'CIDR check'; Badge = @($r.CidrChecks).Count; Tone = $(if (@($r.CidrChecks | Where-Object { $_.Status -like '*aken' }).Count) { 'warn' } else { 'good' }); Note = 'The ranges asked about (-TestCidr): free, taken or partly taken, and by what.' }
            @{ Name = 'Findings'; Badge = @($r.Findings).Count; Tone = $(if ($s.High) { 'bad' } else { 'warn' }); Note = 'What to act on, worst first.' }
        )
        Tables   = @(
            @{ Id = 'spaces'; Title = 'Spaces'; Section = 'Spaces'; Rows = @($r.Spaces); Noun = 'spaces'; ConsoleLimit = 10
                Hover = @('Description', 'Blocks', 'Size', 'Allocated', 'Free', 'Networks', 'Subnets', 'IpsUsed', 'Overlaps', 'Findings')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Blocks'; Label = 'Blocks'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'AllocatedPercent'; Label = '% allocated'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Size'; Label = 'Addresses'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Allocated'; Label = 'Allocated'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Free'; Label = 'Free'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true }
                    @{ Key = 'Networks'; Label = 'Networks'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subnets'; Label = 'Subnets'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'IpsUsed'; Label = 'IPs in use'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Overlaps'; Label = 'Overlaps'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Findings'; Label = 'Findings'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide' }
                ) }
            @{ Id = 'blocks'; Title = 'Blocks'; Section = 'Blocks'; Rows = @($r.Blocks); Noun = 'blocks'; GroupBy = @('Space', 'Status'); ConsoleLimit = 20
                HoverTitle = 'Block'; Hover = @('Cidr', 'Range', 'Size', 'Allocated', 'Free', 'LargestFree', 'FreeRanges', 'Next', 'Fits', 'NetworkNames', 'Description')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true; Console = $multiSpace; Pdf = $multiSpace }
                    @{ Key = 'Block'; Label = 'Block'; Console = $true; Pdf = $true }
                    @{ Key = 'Cidr'; Label = 'CIDR'; Type = 'mono'; Console = $true; Pdf = $true; Tip = 'Range' }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true; Tip = 'FreeRanges' }
                    @{ Key = 'AllocatedPercent'; Label = '% allocated'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Networks'; Label = 'Networks'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Pdf = $true; Tip = 'NetworkNames' }
                    @{ Key = 'Size'; Label = 'Addresses'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Allocated'; Label = 'Allocated'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Free'; Label = 'Free'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true }
                    @{ Key = 'LargestFree'; Label = 'Largest free'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Next'; Label = "Next $next"; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Fits'; Label = "Free $next"; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true }
                    @{ Key = 'IpsUsed'; Label = 'IPs in use'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'FreeRanges'; Label = 'Free ranges (largest)'; Type = 'wide' }
                    @{ Key = 'Range'; Label = 'Range'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'NetworkNames'; Label = 'Networks in it'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                ) }
            @{ Id = 'networks'; Title = 'Networks'; Section = 'Networks'; Rows = @($r.Networks); Noun = 'networks'; GroupBy = @('Space', 'Status', 'Kind', 'Subscription'); ConsoleLimit = 25
                HoverTitle = 'Network'; Hover = @('Kind', 'Prefixes', 'Block', 'Status', 'Subnets', 'Used', 'Available', 'Unallocated', 'DnsServers', 'PeeredWith', 'Overlaps', 'IpamReservation', 'Subscription', 'ResourceGroup', 'Location', 'Description')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true; Console = $multiSpace; Pdf = $multiSpace }
                    @{ Key = 'Network'; Label = 'Network'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Kind'; Label = 'Kind'; Type = 'badge'; Tones = $kindTones; Facet = $true }
                    @{ Key = 'Prefixes'; Label = 'Prefixes'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Status'; Label = 'In the plan'; Type = 'badge'; Tones = $managedTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Block'; Label = 'Block'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subnets'; Label = 'Subnets'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'UsedPercent'; Label = '% of subnets used'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Used'; Label = 'Used'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Available'; Label = 'Available'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Unallocated'; Label = 'In no subnet'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'DnsServers'; Label = 'DNS servers'; Facet = $true }
                    @{ Key = 'Peerings'; Label = 'Peerings'; Type = 'number'; Tip = 'PeeredWith' }
                    @{ Key = 'Overlaps'; Label = 'Overlaps'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true }
                    @{ Key = 'IpamReservation'; Label = 'IPAM reservation tag'; Type = 'mono' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'Location'; Label = 'Location'; Facet = $true }
                    @{ Key = 'PeeredWith'; Label = 'Peered with'; Type = 'wide'; Hidden = $true }
                    @{ Key = 'Description'; Label = 'Description'; Type = 'wide'; Hidden = $true }
                ) }
            @{ Id = 'subnets'; Title = 'Subnets'; Section = 'Subnets'; Rows = @($r.Subnets); Noun = 'subnets'; GroupBy = @('Network', 'Status', 'Purpose'); ConsoleLimit = 25
                HoverTitle = 'Subnet'; Hover = @('Prefix', 'Range', 'UsableRange', 'Usable', 'Used', 'Available', 'UsedPercent', 'Purpose', 'Kinds', 'Delegation')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true; Console = $multiSpace }
                    @{ Key = 'Network'; Label = 'Network'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subnet'; Label = 'Subnet'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Prefix'; Label = 'Prefix'; Type = 'mono'; Console = $true; Pdf = $true; Tip = 'UsableRange' }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $statusTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'UsedPercent'; Label = '% used'; Type = 'number'; Format = 'N1'; Console = $true; Pdf = $true }
                    @{ Key = 'Usable'; Label = 'Usable'; Type = 'number'; Format = 'N0'; Sum = $true }
                    @{ Key = 'Used'; Label = 'Used'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Tip = 'Kinds' }
                    @{ Key = 'Available'; Label = 'Available'; Type = 'number'; Format = 'N0'; Sum = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Purpose'; Label = 'Purpose'; Facet = $true; Console = $true }
                    @{ Key = 'Kinds'; Label = 'What takes the addresses'; Type = 'wide' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'Range'; Label = 'Range'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'UsableRange'; Label = 'Usable range'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Delegation'; Label = 'Delegated to'; Hidden = $true }
                ) }
            @{ Id = 'ipaddresses'; Title = 'IP addresses'; Section = 'IP addresses'; Rows = @($r.IpAddresses); Noun = 'addresses'; GroupBy = @('Network', 'Subnet', 'Kind', 'Allocation'); ConsoleLimit = 30
                Empty = 'No address is in use in these subnets.'; EmptyStatus = 'Info'
                HoverTitle = 'PrivateIp'; Hover = @('PrivateIp', 'Allocation', 'Kind', 'Resource', 'Attached', 'PublicIp', 'Network', 'Subnet', 'SubnetPrefix', 'Subscription', 'ResourceGroup')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true }
                    @{ Key = 'PrivateIp'; Label = 'Private IP'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Network'; Label = 'Network'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Subnet'; Label = 'Subnet'; Facet = $true; Console = $true; Pdf = $true; Tip = 'SubnetPrefix' }
                    @{ Key = 'Kind'; Label = 'Kind'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Resource'; Label = 'Resource'; Type = 'resource'; Console = $true; Pdf = $true }
                    @{ Key = 'Attached'; Label = 'Attached to'; Console = $true }
                    @{ Key = 'Allocation'; Label = 'Allocation'; Type = 'badge'; Tones = @{ Static = 'violet'; Dynamic = 'neutral' }; Facet = $true }
                    @{ Key = 'PublicIp'; Label = 'Public IP'; Type = 'mono' }
                    @{ Key = 'Subscription'; Label = 'Subscription'; Facet = $true }
                    @{ Key = 'ResourceGroup'; Label = 'Resource group'; Facet = $true }
                    @{ Key = 'SubnetPrefix'; Label = 'Subnet prefix'; Type = 'mono'; Hidden = $true }
                ) }
            @{ Id = 'overlaps'; Title = 'Overlaps'; Section = 'Overlaps'; Rows = @($r.Overlaps); Noun = 'overlaps'; GroupBy = @('Severity', 'NetworkA'); ConsoleLimit = 20
                Empty = 'No address space overlaps.'; EmptyStatus = 'Success'
                HoverTitle = 'Overlap'; Hover = @('NetworkA', 'KindA', 'PrefixA', 'NetworkB', 'KindB', 'PrefixB', 'Overlap', 'Addresses', 'Peered', 'Impact')
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true }
                    @{ Key = 'NetworkA'; Label = 'Network'; Console = $true; Pdf = $true }
                    @{ Key = 'PrefixA'; Label = 'Prefix'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'NetworkB'; Label = 'Overlaps'; Console = $true; Pdf = $true }
                    @{ Key = 'PrefixB'; Label = 'Its prefix'; Type = 'mono'; Console = $true; Pdf = $true }
                    @{ Key = 'Overlap'; Label = 'Shared range'; Type = 'mono'; Console = $true; Tip = 'Impact' }
                    @{ Key = 'Addresses'; Label = 'Addresses'; Type = 'number' }
                    @{ Key = 'Peered'; Label = 'Peered'; Type = 'badge'; Tones = @{ True = 'bad'; False = 'neutral' }; Facet = $true; Console = $true }
                    @{ Key = 'KindA'; Label = 'Kind'; Facet = $true; Hidden = $true }
                    @{ Key = 'KindB'; Label = 'Its kind'; Facet = $true; Hidden = $true }
                    @{ Key = 'Impact'; Label = 'Impact'; Type = 'wide'; Pdf = $true }
                ) }
            @{ Id = 'next'; Title = "Next available ranges"; Section = 'Free space'; Rows = @($r.NextAvailable); Noun = 'ranges'; GroupBy = @('Size', 'Block'); ConsoleLimit = 20
                HoverTitle = 'Candidate'; Hover = @('Candidate', 'Range', 'Addresses', 'Fit', 'FromFreeRange', 'Fits', 'Why')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true; Console = $multiSpace }
                    @{ Key = 'Block'; Label = 'Block'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Size'; Label = 'Size'; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Candidate'; Label = 'Next range'; Type = 'mono'; Console = $true; Pdf = $true; Tip = 'Range' }
                    @{ Key = 'Fit'; Label = 'Choice'; Type = 'badge'; Tones = $fitTones; Facet = $true; Console = $true; Pdf = $true; Tip = 'Why' }
                    @{ Key = 'FromFreeRange'; Label = 'From free range'; Type = 'mono'; Console = $true }
                    @{ Key = 'Fits'; Label = 'How many fit'; Type = 'number'; Console = $true; Pdf = $true }
                    @{ Key = 'Range'; Label = 'Range'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Addresses'; Label = 'Addresses'; Type = 'number'; Hidden = $true }
                    @{ Key = 'Why'; Label = 'Why'; Type = 'wide' }
                ) }
            @{ Id = 'free'; Title = 'Free ranges'; Section = 'Free space'; Rows = @($r.FreeRanges); Noun = 'free ranges'; GroupBy = @('Block', 'Length'); ConsoleLimit = 15; NoConsole = $true
                HoverTitle = 'FreeRange'; Hover = @('FreeRange', 'Range', 'Addresses', 'Block')
                Columns = @(
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true }
                    @{ Key = 'Block'; Label = 'Block'; Facet = $true; Pdf = $true }
                    @{ Key = 'FreeRange'; Label = 'Free range'; Type = 'mono'; Pdf = $true; Tip = 'Range' }
                    @{ Key = 'Length'; Label = 'Size'; Facet = $true; Pdf = $true }
                    @{ Key = 'Addresses'; Label = 'Addresses'; Type = 'number'; Format = 'N0'; Sum = $true; Pdf = $true }
                    @{ Key = 'Range'; Label = 'Range'; Type = 'mono' }
                ) }
            @{ Id = 'checks'; Title = 'CIDR check'; Section = 'CIDR check'; Rows = @($r.CidrChecks); Noun = 'ranges'; ConsoleLimit = 20
                HoverTitle = 'Cidr'; Hover = @('Range', 'Addresses', 'Status', 'Space', 'Block', 'ConflictsWith', 'Detail')
                Columns = @(
                    @{ Key = 'Cidr'; Label = 'Range asked'; Type = 'mono'; Console = $true; Pdf = $true; Tip = 'Range' }
                    @{ Key = 'Status'; Label = 'Status'; Type = 'badge'; Tones = $checkTones; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Space'; Label = 'Space'; Console = $true }
                    @{ Key = 'Block'; Label = 'Block'; Console = $true; Pdf = $true }
                    @{ Key = 'ConflictsWith'; Label = 'Taken by'; Type = 'wide'; Console = $true; Pdf = $true }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide' }
                    @{ Key = 'Range'; Label = 'Range'; Type = 'mono'; Hidden = $true }
                    @{ Key = 'Addresses'; Label = 'Addresses'; Type = 'number'; Hidden = $true }
                ) }
            @{ Id = 'findings'; Title = 'Findings'; Section = 'Findings'; Rows = @($r.Findings); Noun = 'findings'; GroupBy = @('Finding', 'Severity', 'Category', 'Space'); ConsoleLimit = 25
                Empty = 'Nothing to act on.'; EmptyStatus = 'Success'
                HoverTitle = 'Finding'; Hover = @('Detail', 'Recommendation')
                Columns = @(
                    @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Tones = $rank.Tone; Facet = $true; Console = $true; Pdf = $true }
                    @{ Key = 'Category'; Label = 'Category'; Facet = $true; Console = $true }
                    @{ Key = 'Space'; Label = 'Space'; Facet = $true }
                    @{ Key = 'Item'; Label = 'Item'; Console = $true; Pdf = $true }
                    @{ Key = 'Finding'; Label = 'Finding'; Facet = $true; Console = $true; Pdf = $true; Tip = 'Detail' }
                    @{ Key = 'Detail'; Label = 'Detail'; Type = 'wide'; Pdf = $true }
                    @{ Key = 'Recommendation'; Label = 'What to do'; Type = 'wide'; Pdf = $true }
                ) }
        )
        Hint     = '-AddressPlan sets your spaces and blocks; -NextAvailable 24, 22 the sizes to find; -TestCidr checks ranges; -View Network, Subnet, IpAddress, Overlap or NextAvailable returns those rows; -Open shows the HTML report.'
    }
    $rows = @(switch ($View) {
            'Space' { $r.Spaces }
            'Network' { $r.Networks }
            'Subnet' { $r.Subnets }
            'IpAddress' { $r.IpAddresses }
            'Overlap' { $r.Overlaps }
            'FreeRange' { $r.FreeRanges }
            'NextAvailable' { $r.NextAvailable }
            'CidrCheck' { $r.CidrChecks }
            'Finding' { $r.Findings }
            default { $r.Blocks }
        })
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject $rows -Noun $View.ToLowerInvariant() -CsvPath (& $resolve $CsvPath) -HtmlPath $htmlFullPath -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object $rows -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
    if ($Open -and $htmlFullPath -and (Test-Path -LiteralPath $htmlFullPath)) { Open-AACFile -Path $htmlFullPath }
}
