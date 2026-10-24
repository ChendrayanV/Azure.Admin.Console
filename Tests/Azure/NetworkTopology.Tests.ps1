<#
    Unit tests for Show-AACNetworkTopology: the topology built from a made-up
    Contoso hub and spokes (Fixtures\ContosoTopology.ps1) - roles, the boxes
    around the networks (management groups, subscriptions, regions), NICs
    drawn as part of their VMs, appliances, peerings (and what isn't one),
    networks you can't see, findings - and the command with Azure Resource
    Graph mocked. The page's layouts run in a browser and are not tested here.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoTopology.ps1')
    $script:rows = @(Get-AACContosoTopology)
    $script:subscriptions = @(Get-AACContosoTopologySubscription)
    $script:build = {
        param([string] $GroupBy = 'ManagementGroup', [object[]] $Rows = $script:rows)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Rows = $Rows; Subscriptions = $script:subscriptions; GroupBy = $GroupBy } {
            param($Rows, $Subscriptions, $GroupBy)
            $asset = Get-AACResourceMapAsset
            $labels = @{}
            foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = $asset.Icons.icons[$key].label }
            $names = @{}
            foreach ($s in $Subscriptions) { $names[$s.subscriptionId] = $s.name }
            $map = ConvertTo-AACResourceMap -Resource $Rows -SubscriptionName $names -IconType $asset.Icons.types -IconLabel $labels
            ConvertTo-AACNetworkTopology -Map $map -Resource $Rows -Subscription $Subscriptions -GroupBy $GroupBy
        }
    }
    $script:vnet = { param($Map, [string] $Name) $Map.Clusters | Where-Object { $_.kind -eq 'vnet' -and $_.name -eq $Name } | Select-Object -First 1 }
    $script:chain = {
        # The kinds of the boxes around a box, innermost first.
        param($Map, $Item)
        $byId = @{}
        foreach ($c in $Map.Clusters) { $byId[$c.id] = $c }
        $p = $Item.parent
        while ($p -and $byId.Contains($p)) { $byId[$p].kind; $p = $byId[$p].parent }
    }
}

Describe 'Azure Admin Console - network topology' {
    BeforeAll { $script:m = & $script:build }

    It 'gives each network its role: hub, spoke of which hub, standalone, outside your view' {
        $hub = & $script:vnet $script:m 'vnet-hub'
        $hub.role | Should -Be 'hub'
        (& $script:vnet $script:m 'vnet-spoke-app').role | Should -Be 'spoke'
        (& $script:vnet $script:m 'vnet-spoke-app').hub | Should -Be $hub.id
        (& $script:vnet $script:m 'vnet-spoke-data').role | Should -Be 'spoke'
        (& $script:vnet $script:m 'vnet-lab').role | Should -Be 'standalone'
        $partner = & $script:vnet $script:m 'vnet-partner'
        $partner.external | Should -BeTrue
        $partner.detail | Should -Contain 'outside your view'
        $script:m.Layout | Should -Be 'hubspoke'
        "$($script:m.Stats.Networks) $($script:m.Stats.Hubs) $($script:m.Stats.Spokes) $($script:m.Stats.Standalone) $($script:m.Stats.Hidden)" | Should -Be '4 1 2 1 1'
    }

    It 'draws one peering per pair of networks - not a peering''s remoteGateways nor a gateway''s list of peerings' {
        $peerings = @($script:m.Edges | Where-Object { $_.kind -eq 'peering' })
        $peerings.Count | Should -Be 3
        $gateway = ($script:m.Nodes | Where-Object { $_.name -eq 'vgw-hub' }).id
        @($peerings | Where-Object { $_.source -eq $gateway -or $_.target -eq $gateway }) | Should -BeNullOrEmpty
        $toData = $peerings | Where-Object { $_.target -eq (& $script:vnet $script:m 'vnet-spoke-data').id -or $_.source -eq (& $script:vnet $script:m 'vnet-spoke-data').id }
        $toData.warn | Should -BeTrue
        @($peerings | Where-Object { $_.warn }).Count | Should -Be 1
    }

    It 'draws a NIC as part of its VM, and a VM whose NIC forwards IP traffic as an appliance' {
        @($script:m.Nodes | Where-Object { $_.type -eq 'microsoft.network/networkinterfaces' }).name | Should -Be @('nic-leftover') -Because 'it has no VM'
        $web = $script:m.Nodes | Where-Object { $_.name -eq 'vm-web-01' }
        $web.facts | Should -Contain '10.1.1.4'
        (& $script:chain $script:m $web)[0] | Should -Be 'subnet'
        $nva = $script:m.Nodes | Where-Object { $_.name -eq 'vm-nva' }
        $nva.nva | Should -BeTrue
        $nva.typeLabel | Should -Be 'Network virtual appliance'
        $script:m.Stats.Appliances | Should -Be 1
        @($script:m.Edges | Where-Object { $_.source -like '*/networkinterfaces/nic-web-01' -or $_.target -like '*/networkinterfaces/nic-web-01' }) | Should -BeNullOrEmpty
    }

    It 'puts the networks in their tenant, management group, subscription, region and resource group' {
        $hub = & $script:vnet $script:m 'vnet-hub'
        @(& $script:chain $script:m $hub) | Should -Be @('resourcegroup', 'region', 'subscription', 'managementgroup', 'tenant')
        ($script:m.Clusters | Where-Object { $_.kind -eq 'tenant' }).name | Should -Be 'Tenant Root Group'
        @($script:m.Clusters | Where-Object { $_.kind -eq 'managementgroup' } | ForEach-Object { $_.name } | Sort-Object) | Should -Be @('Landing zones', 'Platform')
        @($script:m.Clusters | Where-Object { $_.kind -eq 'region' } | ForEach-Object { $_.name } | Sort-Object) | Should -Be @('uksouth', 'uksouth', 'westeurope') -Because 'a region box per subscription'
        $hub.context | Should -Be 'Contoso Connectivity › uksouth › rg-hub'
        @($script:m.Clusters | Where-Object { $_.kind -eq 'resourcegroup' -and $_.name -eq 'rg-spoke-data' }).Count | Should -Be 1
    }

    It 'groups by subscription or by region instead' {
        $bySub = & $script:build 'Subscription'
        @(& $script:chain $bySub (& $script:vnet $bySub 'vnet-hub')) | Should -Be @('resourcegroup', 'region', 'subscription')
        @($bySub.Clusters | Where-Object { $_.kind -in 'managementgroup', 'tenant' }) | Should -BeNullOrEmpty
        $byRegion = & $script:build 'Region'
        @(& $script:chain $byRegion (& $script:vnet $byRegion 'vnet-lab')) | Should -Be @('region')
        @($byRegion.Clusters | Where-Object { $_.kind -in 'subscription', 'managementgroup' }) | Should -BeNullOrEmpty
    }

    It 'finds what to look at: a peering not connected, egress not inspected, a network you can''t see, a standalone network' {
        @($script:m.Findings | ForEach-Object { "$($_.Severity)|$($_.Finding)|$($_.Resource)" }) | Should -Be @(
            'High|Peering not connected|vnet-hub <-> vnet-spoke-data'
            'High|Route to an unknown next hop|rt-spoke'
            'Medium|Egress not inspected|vnet-spoke-data/snet-data'
            'Info|Peered with a network you can''t see|vnet-hub'
            'Info|Standalone network|vnet-lab'
        )
        $script:m.Findings[0].PSObject.TypeNames | Should -Contain 'AAC.NetworkTopologyFinding'
        # snet-web sends 0.0.0.0/0 to the hub's firewall: inspected.
        ($script:m.Clusters | Where-Object { $_.kind -eq 'subnet' -and $_.name -eq 'snet-web' }).egress | Should -Be 'inspected'
    }

    It 'sizes a subnet by its prefix' {
        ($script:m.Clusters | Where-Object { $_.kind -eq 'subnet' -and $_.name -eq 'snet-web' }).prefixLength | Should -Be 24
        ($script:m.Clusters | Where-Object { $_.kind -eq 'subnet' -and $_.name -eq 'GatewaySubnet' }).prefixLength | Should -Be 27
    }
}

Describe 'Azure Admin Console - Show-AACNetworkTopology' {
    BeforeEach {
        $script:queries = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $script:queries.Add(@{ Query = $Query; SubscriptionId = $SubscriptionId; ManagementGroupId = $ManagementGroupId })
            $rows = @{}
            foreach ($name in @($Query.Keys)) {
                $spec = $Query[$name]
                $text = if ($spec -is [System.Collections.IDictionary]) { [string]$spec['Query'] } else { [string]$spec }
                $rows[$name] = @(
                    if ($name -eq 'subscriptions') { $script:subscriptions }
                    elseif ($text -match 'where id in~') { $script:rows | Where-Object { $text -match [regex]::Escape("'$($_.id)'") } }
                    elseif ($name -eq 'appliances') { $script:rows | Where-Object { $_.type -eq 'Microsoft.Network/networkInterfaces' -and $_.properties['enableIPForwarding'] -eq $true } }
                    elseif ($name -eq 'resources') {
                        $script:rows | Where-Object { $text -match [regex]::Escape("'$($_.type.ToLowerInvariant())'") -and ($text -notmatch 'location in~' -or $text -match [regex]::Escape("'$($_.location)'")) }
                    }
                )
            }
            @{ Rows = $rows; Errors = @{} }
        }
    }

    It 'draws the topology, writes the page, opens it, and returns the networks and findings' {
        $path = Join-Path $TestDrive 'topology.html'
        $t = Show-AACNetworkTopology -HtmlPath $path -PassThru
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 1 -Exactly -ParameterFilter { $Path -eq $path }
        $t.PSObject.TypeNames | Should -Contain 'AAC.NetworkTopology'
        ($t.Networks | Where-Object Name -EQ 'vnet-spoke-app').Role | Should -Be 'spoke'
        ($t.Networks | Where-Object Name -EQ 'vnet-spoke-app').Hub | Should -Be 'vnet-hub'
        ($t.Networks | Where-Object Name -EQ 'vnet-hub').AddressSpace | Should -Match '^10\.0\.'
        @($t.Findings | Where-Object Severity -EQ 'High').Finding | Should -Be @('Peering not connected', 'Route to an unknown next hop')
        $html = Get-Content -LiteralPath $path -Raw
        $model = [regex]::Match($html, '<script id="aac-map" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.options.layout | Should -Be 'hubspoke'
        $model.options.hierarchy | Should -Be 'packed'
        $model.options.hubSpoke | Should -BeTrue
        # The private endpoint's SQL server is outside the network types: looked up by ID, drawn outside.
        ($t.Nodes | Where-Object Name -EQ 'sql-orders').Outside | Should -BeTrue
        @($t.Edges | Where-Object Kind -EQ 'privatelink').Count | Should -Be 1
    }

    It 'leaves out VMs, scale sets and private endpoints with -NetworkOnly, but keeps the appliances' {
        $t = Show-AACNetworkTopology -NetworkOnly -NoBrowser -HtmlPath (Join-Path $TestDrive 'fabric.html') -PassThru
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 0 -Exactly
        @($t.Nodes | Where-Object { $_.Type -in 'microsoft.compute/virtualmachines' } | ForEach-Object Name) | Should -Be @('vm-nva')
        @($t.Nodes | Where-Object { $_.Type -eq 'microsoft.network/privateendpoints' }) | Should -BeNullOrEmpty
        ($t.Nodes | Where-Object Name -EQ 'vm-nva').Appliance | Should -BeTrue
    }

    It 'scopes to management groups and regions, and lays out the hierarchy when asked' {
        $path = Join-Path $TestDrive 'region.html'
        $t = Show-AACNetworkTopology -ManagementGroupId 'mg-landingzones' -Location 'westeurope' -Layout Hierarchy -GroupBy Region -NoBrowser -HtmlPath $path -PassThru
        $first = $script:queries[0]
        @($first.ManagementGroupId) | Should -Be @('mg-landingzones')
        [string]$first.Query['resources'] | Should -Match "location in~ \('westeurope'\)"
        $first.Query['subscriptions'].Tenant | Should -BeTrue -Because 'subscription names come from the whole tenant'
        @($t.Networks | Where-Object { -not $_.Outside } | ForEach-Object Name | Sort-Object) | Should -Be @('vnet-lab', 'vnet-spoke-data')
        @($t.Findings | Where-Object Finding -EQ 'Peered with a network you can''t see') | Should -BeNullOrEmpty -Because 'the hub is outside the scope, not out of sight, and its own peerings aren''t followed'
        $model = [regex]::Match((Get-Content -LiteralPath $path -Raw), '<script id="aac-map" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value | ConvertFrom-Json
        $model.options.layout | Should -Be 'packed'
        $t.Title | Should -Be 'Network topology: management group mg-landingzones (westeurope)'
    }

    It 'says so when there are no networks' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { $rows = @{}; foreach ($n in @($Query.Keys)) { $rows[$n] = @() }; @{ Rows = $rows; Errors = @{} } }
        $t = Show-AACNetworkTopology -NoBrowser -HtmlPath (Join-Path $TestDrive 'empty.html') -PassThru
        $t.Stats.Networks | Should -Be 0
        @($t.Networks) | Should -BeNullOrEmpty
    }
}
