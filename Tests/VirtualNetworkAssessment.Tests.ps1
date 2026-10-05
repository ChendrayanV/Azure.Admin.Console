<#
    Unit tests for Invoke-AACVirtualNetworkAssessment: the CIDR arithmetic,
    the assessment of a made-up Contoso network (Fixtures\ContosoNetwork.ps1)
    - address space and IPs, subnets, peerings, ASGs, private endpoints and
    every finding - and the command with Azure Resource Graph mocked: scope,
    filters, the view and the exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
    $script:canWritePdf = $IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4'
    $script:expectedFindings = @(
        @{ Severity = 'High'; Finding = 'Subnet full'; Network = 'vnet-spoke-app'; Item = 'snet-full' }
        @{ Severity = 'High'; Finding = 'AzureBastionSubnet is smaller than /26'; Network = 'vnet-hub-weu'; Item = 'AzureBastionSubnet' }
        @{ Severity = 'High'; Finding = 'Default route on GatewaySubnet'; Network = 'vnet-hub-weu'; Item = 'GatewaySubnet' }
        @{ Severity = 'High'; Finding = 'NSG on GatewaySubnet'; Network = 'vnet-hub-weu'; Item = 'GatewaySubnet' }
        @{ Severity = 'High'; Finding = 'Peering Initiated'; Network = 'vnet-hub-weu'; Item = 'hub-to-spoke-old' }
        @{ Severity = 'High'; Finding = 'NSG: Open to the internet'; Network = 'vnet-spoke-app'; Item = 'nsg-web / allow-rdp-internet' }
        @{ Severity = 'Medium'; Finding = 'Subnet nearly full'; Network = 'vnet-spoke-app'; Item = 'snet-web' }
        @{ Severity = 'Medium'; Finding = 'GatewaySubnet is smaller than /27'; Network = 'vnet-hub-weu'; Item = 'GatewaySubnet' }
        @{ Severity = 'Medium'; Finding = 'Peering out of sync'; Network = 'vnet-spoke-app'; Item = 'spoke-app-to-hub' }
        @{ Severity = 'Medium'; Finding = 'Private endpoint Pending'; Network = 'vnet-spoke-app'; Item = 'pe-vault' }
        @{ Severity = 'Medium'; Finding = 'Private endpoints without their private DNS zone'; Network = 'vnet-spoke-app'; Item = '' }
        @{ Severity = 'Medium'; Finding = 'No virtual network flow logs'; Network = 'vnet-spoke-app'; Item = '' }
        @{ Severity = 'Medium'; Finding = 'No DDoS Network Protection'; Network = 'vnet-hub-weu'; Item = '' }
        @{ Severity = 'Medium'; Finding = 'No DDoS Network Protection'; Network = 'vnet-spoke-app'; Item = '' }
        @{ Severity = 'Medium'; Finding = 'Relies on default outbound access'; Network = 'vnet-spoke-app'; Item = 'snet-web' }
        @{ Severity = 'Medium'; Finding = 'Subnet without an NSG'; Network = 'vnet-spoke-app'; Item = 'snet-pe' }
        @{ Severity = 'Medium'; Finding = 'VMs reachable on public IPs'; Network = 'vnet-spoke-app'; Item = 'snet-web' }
        @{ Severity = 'Low'; Finding = 'Oversized subnet'; Network = 'vnet-spoke-old'; Item = 'snet-big' }
        @{ Severity = 'Low'; Finding = 'Gateway transit without forwarded traffic'; Network = 'vnet-spoke-app'; Item = 'spoke-app-to-hub' }
        @{ Severity = 'Low'; Finding = 'Overlapping address space'; Network = 'vnet-spoke-app'; Item = 'vnet-spoke-old' }
        @{ Severity = 'Low'; Finding = 'Overlapping address space'; Network = 'vnet-spoke-old'; Item = 'vnet-spoke-app' }
        @{ Severity = 'Low'; Finding = 'Unused application security group'; Network = ''; Item = 'asg-orphan' }
        @{ Severity = 'Low'; Finding = 'NSG rules name an empty application security group'; Network = ''; Item = 'asg-db' }
        @{ Severity = 'Low'; Finding = 'Unused virtual network'; Network = 'vnet-spoke-old'; Item = '' }
        @{ Severity = 'Low'; Finding = 'Gateway not zone-redundant'; Network = 'vnet-hub-weu'; Item = 'vpngw-hub' }
        @{ Severity = 'Low'; Finding = 'Single custom DNS server'; Network = 'vnet-hub-weu'; Item = '' }
        @{ Severity = 'Low'; Finding = 'Subnet without an NSG'; Network = 'vnet-hub-weu'; Item = 'snet-dns' }
        @{ Severity = 'Low'; Finding = 'Subnet without an NSG'; Network = 'vnet-spoke-old'; Item = 'snet-legacy' }
        @{ Severity = 'Low'; Finding = 'Subnet without an NSG'; Network = 'vnet-spoke-old'; Item = 'snet-big' }
        @{ Severity = 'Low'; Finding = 'Private endpoint network policies off'; Network = 'vnet-spoke-app'; Item = 'snet-pe' }
        @{ Severity = 'Low'; Finding = 'Virtual network encryption off'; Network = 'vnet-spoke-app'; Item = '' }
        @{ Severity = 'Info'; Finding = 'Remote network not visible'; Network = 'vnet-hub-weu'; Item = 'hub-to-hub-eus' }
        # The NSG engine's findings on the NSGs these networks use.
        @{ Severity = 'Medium'; Finding = 'NSG: No flow logs'; Network = 'vnet-spoke-app'; Item = 'nsg-app' }
        @{ Severity = 'Low'; Finding = 'NSG: Flow log retention'; Network = 'vnet-spoke-app'; Item = 'nsg-web' }
        @{ Severity = 'Info'; Finding = 'NSG: NSG flow log retiring'; Network = 'vnet-spoke-app'; Item = 'nsg-web' }
        @{ Severity = 'Info'; Finding = 'NSG: Traffic Analytics off'; Network = 'vnet-spoke-app'; Item = 'nsg-web' }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoNetwork.ps1')
    $script:f = Get-AACContosoNetwork
    # The NSG engine's inputs, as the command builds them.
    $script:assess = {
        param([hashtable] $With = @{}, [hashtable] $Fixture = $script:f)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ F = $Fixture; With = $With } {
            param($F, $With)
            $p = @{}
            foreach ($key in $F.Converter.Keys) { $p[$key] = $F.Converter[$key] }
            foreach ($key in $With.Keys) { $p[$key] = $With[$key] }
            $subnets = @(foreach ($vnet in $p.VirtualNetwork) { foreach ($subnet in $vnet.properties.subnets) { @{ subnetId = $subnet.id.ToLowerInvariant(); name = $subnet.name; vnetId = $vnet.id.ToLowerInvariant(); vnetName = $vnet.name; prefix = $subnet.properties.addressPrefix; nsg = $(if ($subnet.properties.Contains('networkSecurityGroup')) { $subnet.properties.networkSecurityGroup.id.ToLowerInvariant() } else { '' }) } } })
            $nics = @(foreach ($nic in $p.NetworkInterface) { @{ id = $nic.id; name = $nic.name; resourceGroup = $nic.resourceGroup; nsg = $nic.nsg; vm = $nic.vm; subnet = $nic.ipConfigurations[0].properties.subnet.id; ips = @(); asgs = @() } })
            $p['NsgAssessment'] = ConvertTo-AACNsgAssessment -NetworkSecurityGroup $p.NetworkSecurityGroup -NetworkInterface $nics -Subnet $subnets -FlowLog $p.FlowLog -Diagnostic $null -SubscriptionName $p.SubscriptionName
            ConvertTo-AACVirtualNetworkAssessment @p
        }
    }
    $script:a = & $script:assess
    $script:vnet = { param([string] $Name) $script:a.VirtualNetworks | Where-Object Name -EQ $Name }
    $script:subnet = { param([string] $Name) $script:a.Subnets | Where-Object Subnet -EQ $Name }
    $script:capture = {
        param([scriptblock] $Render, [switch] $Ascii)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 200
        $console.Profile.Capabilities.Unicode = -not $Ascii
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - CIDR arithmetic' {
    It 'reads a prefix: its range, size and length' {
        $range = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange '10.0.1.0/24' }
        "$($range.Size) $($range.Length) $($range.Valid)" | Should -Be '256 24 True'
        $range.End - $range.Start | Should -Be 255
        (InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange '10.0.0.300/24' }).Valid | Should -BeFalse
        (InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange 'fd00:db8::/64' }).Version | Should -Be 6
    }

    It 'finds the free blocks of an address space as the largest aligned CIDRs' {
        $free = @(InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange -Space '10.0.0.0/16' -Used '10.0.0.0/24', '10.0.1.0/24', '10.0.4.0/22' })
        @($free.Prefix) | Should -Be @('10.0.2.0/23', '10.0.128.0/17', '10.0.64.0/18', '10.0.32.0/19', '10.0.16.0/20', '10.0.8.0/21')
        @(InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange -Space '10.0.0.0/24' -Used '10.0.0.0/24' }).Count | Should -Be 0
        @(InModuleScope 'Azure.Admin.Console' { ConvertTo-AACCidrRange -Space '10.0.0.0/24' -Used @() }).Prefix | Should -Be '10.0.0.0/24'
    }
}

Describe 'Azure Admin Console - virtual network assessment' {
    It 'counts the address space: total, in subnets, unallocated, usable, used and available' {
        $hub = & $script:vnet 'vnet-hub-weu'
        "$($hub.TotalIps)/$($hub.IpsInSubnets)/$($hub.UnallocatedIps)/$($hub.UsableIps)/$($hub.UsedIps)/$($hub.AvailableIps)" | Should -Be '1024/128/896/108/3/105'
        $app = & $script:vnet 'vnet-spoke-app'
        "$($app.UsableIps)/$($app.UsedIps)/$($app.AvailableIps)/$($app.UsedPercent)" | Should -Be '68/30/38/44.1'
    }

    It 'sizes each subnet: Azure keeps 5 addresses, each IP configuration uses one' {
        $web = & $script:subnet 'snet-web'
        "$($web.Size)/$($web.Usable)/$($web.Used)/$($web.Available)/$($web.UsedPercent)" | Should -Be '32/27/24/3/88.9'
        (& $script:subnet 'snet-full').Available | Should -Be 0
        (& $script:subnet 'AzureBastionSubnet').Purpose | Should -Be 'Azure Bastion'
        (& $script:subnet 'snet-pe').Purpose | Should -Be 'Private endpoints'
    }

    It 'lists the free ranges a new subnet can take, largest first' {
        @(($script:a.FreeRanges | Where-Object VirtualNetwork -EQ 'vnet-spoke-app').Prefix) | Should -Be @('10.1.0.128/25', '10.1.0.96/27', '10.1.0.88/29')
        (& $script:vnet 'vnet-hub-weu').FreeRangeList[0].Prefix | Should -Be '10.0.2.0/23'
    }

    It 'works out each subnet''s outbound path, routes and flow logs' {
        (& $script:subnet 'snet-web').Outbound | Should -Be 'Default outbound access'
        (& $script:subnet 'snet-app').Outbound | Should -Be 'Firewall / NVA (route table)'
        (& $script:subnet 'snet-app').DefaultRoute | Should -Be 'VirtualAppliance 10.0.0.68'
        (& $script:subnet 'snet-app').BgpPropagation | Should -Be 'Disabled'
        (& $script:subnet 'snet-full').Outbound | Should -Be 'None (private subnet)'
        (& $script:subnet 'snet-full').DefaultOutboundAccess | Should -Be 'Off (private subnet)'
        (& $script:subnet 'snet-web').FlowLogs | Should -Be 'NSG flow log'
        (& $script:subnet 'snet-dns').FlowLogs | Should -Be 'VNet flow log'
        (& $script:subnet 'snet-web').PublicIpNics | Should -Be 1
        (& $script:subnet 'snet-web').ServiceEndpoints | Should -Be 'Microsoft.Storage'
    }

    It 'reads the role, DNS, DDoS, flow logs and edge services of each network' {
        $hub = & $script:vnet 'vnet-hub-weu'
        "$($hub.Role)/$((& $script:vnet 'vnet-spoke-app').Role)/$((& $script:vnet 'vnet-spoke-old').Role)" | Should -Be 'Hub/Spoke/Standalone'
        $hub.DnsServers | Should -Be '10.0.1.4'
        $hub.Gateways | Should -Be 'vpngw-hub (Vpn VpnGw1)'
        $hub.Firewalls | Should -Be 'afw-hub (Premium)'
        $hub.Bastions | Should -Be 'bas-hub (Standard)'
        $hub.FlowLogs | Should -Be 'VNet flow log, Traffic Analytics'
        $hub.PublicIps | Should -Be 3
        (& $script:vnet 'vnet-spoke-app').PrivateDnsZones | Should -Be 'privatelink.blob.core.windows.net'
        (& $script:vnet 'vnet-spoke-app').Overlaps | Should -Be 'vnet-spoke-old'
        $hub.Tags | Should -Be 'env=prod; role=hub'
    }

    It 'reads each peering: state, sync, remote network, reverse peering' {
        $peerings = @($script:a.Peerings)
        $peerings.Count | Should -Be 4
        $old = $peerings | Where-Object Peering -EQ 'hub-to-spoke-old'
        "$($old.State)/$($old.ReversePeering)/$($old.RemoteVisible)" | Should -Be 'Initiated/False/True'
        $far = $peerings | Where-Object Peering -EQ 'hub-to-hub-eus'
        $far.RemoteVisible | Should -BeFalse
        $far.RemoteSubscription | Should -Be '33333333-3333-3333-3333-333333333333'
        ($peerings | Where-Object Peering -EQ 'spoke-app-to-hub').RemoteSubscription | Should -Be 'sub-connectivity'
        ($peerings | Where-Object Peering -EQ 'hub-to-spoke-app').ReversePeering | Should -BeTrue
    }

    It 'shows who is in each ASG and which NSG rules name it' {
        $app = $script:a.Asgs | Where-Object Asg -EQ 'asg-app'
        "$($app.Nics)/$($app.Members)/$($app.Rules)" | Should -Be '1/nic-app-1 (vm-app-1)/1'
        ($script:a.Asgs | Where-Object Asg -EQ 'asg-db').RuleNames | Should -Be 'nsg-app/allow-app-to-db (destination)'
    }

    It 'checks each private endpoint''s connection and DNS zone' {
        $blob = $script:a.PrivateEndpoints | Where-Object PrivateEndpoint -EQ 'pe-blob'
        "$($blob.Status)/$($blob.ZoneLinked)/$($blob.TargetType)" | Should -Be 'Approved/Yes/Microsoft.Storage/storageAccounts'
        ($script:a.PrivateEndpoints | Where-Object PrivateEndpoint -EQ 'pe-vault').ZoneLinked | Should -Be 'No'
        ($script:a.Findings | Where-Object Finding -EQ 'Private endpoints without their private DNS zone').Detail | Should -BeLike '*pe-vault (vault: privatelink.vaultcore.azure.net)*'
    }

    It 'finds <Severity>: <Finding> on <Network> <Item>' -ForEach $script:expectedFindings {
        $found = @($script:a.Findings | Where-Object { $_.Severity -eq $Severity -and $_.Finding -eq $Finding -and [string]$_.VirtualNetwork -eq $Network -and [string]$_.Item -eq $Item })
        $found.Count | Should -Be 1
        $found[0].Detail | Should -Not -BeNullOrEmpty
        if ($found[0].Severity -ne 'Info' -or $found[0].Source -eq 'Assessment') { $found[0].Action | Should -Not -BeNullOrEmpty }
    }

    It 'raises nothing more than those, most severe first, and counts them per network' {
        @($script:a.Findings).Count | Should -Be 36 -Because 'the findings above, and no others'
        $script:a.Findings[0].Severity | Should -Be 'High'
        $script:a.Findings[-1].Severity | Should -Be 'Info'
        "$($script:a.Stats.High)/$($script:a.Stats.Medium)/$($script:a.Stats.Low)/$($script:a.Stats.Info)" | Should -Be '6/12/15/3'
        $hub = & $script:vnet 'vnet-hub-weu'
        "$($hub.High)/$($hub.Medium)/$($hub.Low)" | Should -Be '4/2/3'
        @($hub.Findings | Where-Object Finding -EQ 'Gateway not zone-redundant').Count | Should -Be 1 -Because 'the gateway''s findings count for its network'
        $script:a.VirtualNetworks[0].Name | Should -Be 'vnet-hub-weu' -Because 'most at risk first'
    }

    It 'attaches each network''s subnets, peerings, free ranges, endpoints and findings to it' {
        $app = & $script:vnet 'vnet-spoke-app'
        @($app.Subnets.Subnet) | Should -Be @('snet-web', 'snet-app', 'snet-pe', 'snet-full')
        @($app.Peerings).Count | Should -Be 1
        @($app.FreeRangeList).Count | Should -Be 3
        @($app.PrivateEndpointList).Count | Should -Be 2
        @($app.Findings | Where-Object Source -EQ 'NSG').Count | Should -Be 5
        $app.PSObject.TypeNames | Should -Contain 'AAC.VirtualNetwork'
    }

    It 'suggests Bastion where VMs have public IPs and no hub is peered' {
        $alone = Get-AACContosoNetwork
        $alone.Converter.VirtualNetwork[1].properties.virtualNetworkPeerings = @()
        $result = & $script:assess -Fixture $alone -With @{ VirtualNetwork = @($alone.Converter.VirtualNetwork[1]) }
        @($result.Findings | Where-Object Finding -EQ 'No Azure Bastion').Count | Should -Be 1
        ($result.VirtualNetworks[0]).Role | Should -Be 'Standalone'
    }

    It 'flags a Basic gateway, and DDoS IP Protection counts' {
        $basic = Get-AACContosoNetwork
        $basic.Converter.Gateway[0].sku = 'Basic'
        foreach ($ip in $basic.Converter.PublicIp) { $ip.protectionMode = 'Enabled' }
        $result = & $script:assess -Fixture $basic -With @{ VirtualNetwork = @($basic.Converter.VirtualNetwork[0]) }
        ($result.Findings | Where-Object Finding -EQ 'Basic VPN gateway').Severity | Should -Be 'Medium'
        $result.VirtualNetworks[0].DdosProtection | Should -Be 'IP Protection on 3 IP(s)'
    }

    It 'assesses no networks without failing' {
        $empty = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACVirtualNetworkAssessment -VirtualNetwork @() }
        $empty.Stats.VirtualNetworks | Should -Be 0
        @($empty.Findings).Count | Should -Be 0
    }
}

Describe 'Azure Admin Console - Invoke-AACVirtualNetworkAssessment' {
    BeforeEach {
        $script:failQuery = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{}
            $errors = @{}
            foreach ($key in @($Query.Keys)) {
                $rows[$key] = [System.Collections.Generic.List[object]]::new()
                if ($script:failQuery -contains $key) { $errors[$key] = 'Forbidden'; continue }
                foreach ($row in @($script:f.Rows[$key])) {
                    if ($key -eq 'vnets') {
                        if ($SubscriptionId -and @($SubscriptionId) -notcontains $row.subscriptionId) { continue }
                        if ($Query[$key] -match 'resourceGroup in~ \(([^)]*)\)' -and $Matches[1] -notmatch "'$($row.resourceGroup)'") { continue }
                    }
                    $rows[$key].Add($row)
                }
            }
            @{ Rows = $rows; Errors = $errors }
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'assesses every network with no parameters, and returns the objects' {
        $vnets = @(Invoke-AACVirtualNetworkAssessment -NoDisplay)
        $vnets.Count | Should -Be 3
        $vnets[0].PSObject.TypeNames | Should -Contain 'AAC.VirtualNetwork'
        ($vnets | Where-Object Name -EQ 'vnet-spoke-app').UsedIps | Should -Be 30
        @($vnets.Findings | Where-Object Finding -EQ 'NSG: Open to the internet').Count | Should -Be 1 -Because 'the NSGs on the networks are assessed as Get-AACNetworkSecurityGroup does'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { $Query.Contains('nics') -and @($SubscriptionId).Count -eq 2 } -Times 1 -Exactly -Because 'what is around the networks is read in their subscriptions'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -ParameterFilter { $Query.Contains('allVnets') -and -not $SubscriptionId } -Times 1 -Exactly -Because 'remote peerings and overlaps need every network the account can see'
    }

    It 'filters by subscription, resource group and name (with wildcards), and says what it can''t find' {
        @((Invoke-AACVirtualNetworkAssessment -SubscriptionId $script:f.HubSubscriptionId -NoDisplay).Name) | Should -Be @('vnet-hub-weu')
        @((Invoke-AACVirtualNetworkAssessment -ResourceGroupName 'rg-legacy' -NoDisplay).Name) | Should -Be @('vnet-spoke-old')
        @((Invoke-AACVirtualNetworkAssessment -Name 'vnet-spoke-*' -NoDisplay).Name) | Sort-Object | Should -Be @('vnet-spoke-app', 'vnet-spoke-old')
        $null = Invoke-AACVirtualNetworkAssessment -Name 'vnet-hub-weu', 'vnet-typo' -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -BeLike "*No virtual network named 'vnet-typo'*"
        { Invoke-AACVirtualNetworkAssessment -Name 'vnet-nope' -NoDisplay } | Should -Throw "*No virtual network named 'vnet-nope'*"
    }

    It 'carries on when something around the networks can''t be read, and says so' {
        $script:failQuery = @('dnsLinks')
        $vnets = @(Invoke-AACVirtualNetworkAssessment -NoDisplay -WarningVariable warnings -WarningAction SilentlyContinue)
        $vnets.Count | Should -Be 3
        "$warnings" | Should -BeLike '*dnsLinks couldn''t be read*'
    }

    It 'shows the networks, the findings and - for a few - their subnets and peerings, in characters any console can show' {
        $text = (& $script:capture { Invoke-AACVirtualNetworkAssessment -NoPaging } -Ascii).Text
        foreach ($expected in 'Virtual networks', 'vnet-hub-weu', 'HIGH', 'Subnet full', 'Subnets by IPs used', 'Subnets', 'Peerings', 'Free for new subnets', '10.1.0.128/25') { $text | Should -BeLike "*$expected*" }
        foreach ($codePage in 437, 850) {
            $encoding = [System.Text.Encoding]::GetEncoding($codePage)
            @($text.ToCharArray() | Select-Object -Unique | Where-Object { $encoding.GetString($encoding.GetBytes([string]$_)) -ne [string]$_ }) | Should -BeNullOrEmpty
        }
    }

    It 'writes every subnet to CSV, and an HTML report with every table' {
        $csv = Join-Path $TestDrive 'subnets.csv'
        $html = Join-Path $TestDrive 'vnet.html'
        $null = & $script:capture { Invoke-AACVirtualNetworkAssessment -CsvPath $csv -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 10
        ($rows | Where-Object Subnet -EQ 'snet-web').UsedPercent | Should -Be '88.9'
        $model = [regex]::Match((Get-Content -LiteralPath $html -Raw), '<script id="aac-data" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        @($model.tables.id) | Should -Be @('vnets', 'findings', 'subnets', 'peerings', 'free', 'endpoints', 'asgs', 'nsgrules')
        ($model.tables | Where-Object id -EQ 'findings').rows[0].Severity | Should -Be 'High'
        ($model.tiles | Where-Object label -EQ 'high-severity findings').value | Should -Be '6'
        @(($model.tables | Where-Object id -EQ 'vnets').rows[0].PSObject.Properties.Name) | Should -Not -Contain 'Subnets' -Because 'the nested lists have their own tables'
    }

    It 'writes a PDF report' -Skip:(-not $script:canWritePdf) {
        $pdf = Join-Path $TestDrive 'vnet.pdf'
        $null = & $script:capture { Invoke-AACVirtualNetworkAssessment -PdfPath $pdf }
        (Get-Item -LiteralPath $pdf).Length | Should -BeGreaterThan 2000
    }
}
