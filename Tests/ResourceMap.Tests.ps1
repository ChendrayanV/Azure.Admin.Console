<#
    Unit tests for Show-AACResourceMap: the map built from a made-up Contoso
    hub-and-spoke estate (Fixtures\ContosoEstate.ps1) - boxes, placement,
    typed connections, network paths, unattached resources, resources outside
    the selection - the HTML page written from it, and the command with Azure
    Resource Graph mocked. The page's layout and image export run in a
    browser and are not tested here.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/GraphBatchShim.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoEstate.ps1')
    $script:estate = @(Get-AACContosoEstate)
    $script:hubSub = '11111111-1111-1111-1111-111111111111'
    $script:appSub = '22222222-2222-2222-2222-222222222222'
    $script:names = @{ $script:hubSub = 'Contoso Connectivity'; $script:appSub = 'Contoso Apps' }
    # Builds the map in the module, from rows (and rows outside the selection).
    $script:build = {
        param([object[]] $Rows, [object[]] $External = @(), [string[]] $ExcludeType = @())
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Rows = $Rows; External = $External; Names = $script:names; ExcludeType = $ExcludeType } {
            param($Rows, $External, $Names, $ExcludeType)
            $asset = Get-AACResourceMapAsset
            $labels = @{}
            foreach ($key in $asset.Icons.icons.Keys) { $labels[$key] = $asset.Icons.icons[$key].label }
            ConvertTo-AACResourceMap -Resource $Rows -External $External -SubscriptionName $Names -IconType $asset.Icons.types -IconLabel $labels -ExcludeType $ExcludeType
        }
    }
    $script:short = { param([string] $Id) ($Id -split '/')[-1] }
    $script:edge = {
        param($Map, [string] $Kind, [string] $A, [string] $B)
        # The comma keeps one match an array (a lone hashtable's .Count is its keys).
        , @($Map.Edges | Where-Object {
                $_.kind -eq $Kind -and (
                    ((& $script:short $_.source) -eq $A -and (& $script:short $_.target) -eq $B) -or
                    ((& $script:short $_.source) -eq $B -and (& $script:short $_.target) -eq $A))
            })
    }
    $script:node = { param($Map, [string] $Name) $Map.Nodes | Where-Object { $_.name -eq $Name } | Select-Object -First 1 }
    $script:map = & $script:build $script:estate
}

Describe 'Azure Admin Console - resource map model' {
    It 'nests the boxes: subscription > resource group > virtual network > subnet' {
        $snet = $script:map.Clusters | Where-Object { $_.kind -eq 'subnet' -and $_.name -eq 'snet-web' }
        $vnet = $script:map.Clusters | Where-Object { $_.id -eq $snet.parent }
        $group = $script:map.Clusters | Where-Object { $_.id -eq $vnet.parent }
        $subscription = $script:map.Clusters | Where-Object { $_.id -eq $group.parent }
        $vnet.name | Should -Be 'vnet-spoke-app'
        $vnet.detail | Should -Contain '10.1.0.0/16'
        $group.name | Should -Be 'rg-spoke-app'
        $subscription.name | Should -Be 'Contoso Apps'
        $snet.detail | Should -Be @('10.1.1.0/24', '3 of 251 IPs used') -Because 'a /24 has 256 addresses, and Azure keeps 5'
        $snet.serviceEndpoints | Should -Be @('Microsoft.Storage')
        $snet.badges | Should -Contain 'NSG: nsg-web'
        $snet.badges | Should -Contain 'UDR: rt-spoke'
        ($script:map.Clusters | Where-Object { $_.name -eq 'snet-integration' }).detail | Should -Contain 'delegated to Microsoft.Web/serverFarms'
    }

    It 'draws a resource in the subnet it has an IP in, and a VM with its network interface' {
        foreach ($case in @(@('nic-web-01', 'snet-web'), @('vm-web-01', 'snet-web'), @('afw-hub', 'azurefirewallsubnet'), @('bas-hub', 'azurebastionsubnet'), @('vgw-hub', 'gatewaysubnet'), @('pe-sql', 'snet-pe'))) {
            & $script:short (& $script:node $script:map $case[0]).parent | Should -Be $case[1] -Because "$($case[0]) is in $($case[1])"
        }
        & $script:short (& $script:node $script:map 'kv-orders').parent | Should -Be 'rg-spoke-app'
        & $script:short (& $script:node $script:map 'app-orders').parent | Should -Be 'rg-spoke-app' -Because 'VNet integration is a connection, not a place'
    }

    It 'types the connections: network, dependency, peering, private link, route and DNS' {
        (& $script:edge $script:map 'network' 'vm-web-01' 'nic-web-01').Count | Should -Be 1
        (& $script:edge $script:map 'network' 'nic-web-02' 'pip-web-02').Count | Should -Be 1
        (& $script:edge $script:map 'network' 'snet-web' 'nsg-web').Count | Should -Be 1
        (& $script:edge $script:map 'network' 'app-orders' 'snet-integration').Count | Should -Be 1
        (& $script:edge $script:map 'dependency' 'app-orders' 'asp-orders').Count | Should -Be 1
        (& $script:edge $script:map 'dependency' 'sqldb-orders' 'sql-orders').Count | Should -Be 1 -Because 'a child resource depends on its parent'
        (& $script:edge $script:map 'dependency' 'appi-orders' 'law-orders').Count | Should -Be 1
        $peering = & $script:edge $script:map 'peering' 'vnet-spoke-app' 'vnet-hub'
        $peering.Count | Should -Be 1 -Because 'both sides list the peering; it is drawn once'
        $peering[0].label | Should -Be 'Connected · forwarded traffic · gateway transit · remote gateway'
        (& $script:edge $script:map 'privatelink' 'pe-sql' 'sql-orders').Count | Should -Be 1
        (& $script:edge $script:map 'dns' 'privatelink.database.windows.net' 'vnet-hub').Count | Should -Be 1
    }

    It 'follows a route table''s next hop to the firewall that owns the IP' {
        $route = & $script:edge $script:map 'route' 'rt-spoke' 'afw-hub'
        $route.Count | Should -Be 1
        $route[0].label | Should -Be '0.0.0.0/0 -> 10.0.1.4'
    }

    It 'draws each link once, from the resource that uses to the one it uses' {
        $pairs = @($script:map.Edges | ForEach-Object { (@($_.source, $_.target) | Sort-Object) -join '|' })
        @($pairs | Group-Object | Where-Object Count -GT 1) | Should -BeNullOrEmpty
        $disk = & $script:edge $script:map 'dependency' 'vm-web-01' 'vm-web-01_osdisk'
        & $script:short $disk[0].source | Should -Be 'vm-web-01'
        # Nothing links a resource to the box it is drawn in.
        (& $script:edge $script:map 'network' 'nic-web-01' 'snet-web').Count | Should -Be 0
    }

    It 'puts NSGs and route tables on what they''re applied to, as chips' {
        $snet = $script:map.Clusters | Where-Object { $_.name -eq 'snet-web' }
        @($snet.chips | ForEach-Object { "$($_.kind):$($_.name):$($_.risk)" }) | Sort-Object | Should -Be @('nsg:nsg-web:high', 'udr:rt-spoke:high')
        @((& $script:node $script:map 'nic-web-02').chips | ForEach-Object { "$($_.kind):$($_.name)" }) | Should -Be @('nsg:nsg-mgmt')
        (& $script:node $script:map 'nsg-web').chip | Should -Be 'nsg'
        @((& $script:node $script:map 'nsg-web').appliedTo | ForEach-Object { & $script:short $_ }) | Should -Be @('snet-web')
        (& $script:node $script:map 'nsg-unused').chip | Should -BeNullOrEmpty -Because 'an NSG on nothing stays a card'
        # Their lines to the subnet are for the cards view only.
        (& $script:edge $script:map 'network' 'snet-web' 'nsg-web')[0].view | Should -Be 'cards'
        (& $script:edge $script:map 'network' 'nic-web-02' 'nsg-mgmt')[0].view | Should -Be 'cards'
    }

    It 'draws a subnet''s routes from the subnet when route tables are chips' {
        $fromSubnet = & $script:edge $script:map 'route' 'snet-web' 'afw-hub'
        $fromSubnet.Count | Should -Be 1
        $fromSubnet[0].view | Should -Be 'chips'
        $fromSubnet[0].label | Should -Be '0.0.0.0/0 via rt-spoke'
        (& $script:edge $script:map 'route' 'rt-spoke' 'afw-hub')[0].view | Should -Be 'cards'
    }

    It 'reads an NSG''s rules - custom and default, application security groups by name - and scores them' {
        $nsg = & $script:node $script:map 'nsg-web'
        $inbound = @($nsg.rules | Where-Object { $_.direction -eq 'Inbound' -and -not $_.isDefault })
        @($inbound.name) | Should -Be @('Allow-HTTPS-In', 'Allow-SSH-Anywhere', 'Allow-AzureLB') -Because 'custom rules by priority'
        ($inbound | Where-Object name -EQ 'Allow-HTTPS-In').destination | Should -BeLike '*asg-web*'
        ($inbound | Where-Object name -EQ 'Allow-HTTPS-In').risk | Should -BeNullOrEmpty -Because 'HTTPS from the internet is what a web tier is for'
        ($inbound | Where-Object name -EQ 'Allow-SSH-Anywhere').risk | Should -Be 'high'
        ($inbound | Where-Object name -EQ 'Allow-SSH-Anywhere').reason | Should -Be 'SSH (22) open to the internet.'
        ($inbound | Where-Object name -EQ 'Allow-AzureLB').risk | Should -BeNullOrEmpty
        @($nsg.rules | Where-Object isDefault).Count | Should -Be 3
        $nsg.risk | Should -Be 'high'
        ((& $script:node $script:map 'nsg-mgmt').rules | Where-Object name -EQ 'Allow-RDP').reason | Should -Be 'RDP (3389) open to the internet.'
    }

    It 'scores what an NSG opens to the internet: every port, a management port, a wide range' {
        $nsg = {
            param([string] $Name, [string] $Ports, [string] $Source = 'Internet')
            @{ id = "/subscriptions/$script:appSub/resourceGroups/rg-x/providers/Microsoft.Network/networkSecurityGroups/$Name"; name = $Name; type = 'Microsoft.Network/networkSecurityGroups'; resourceGroup = 'rg-x'; subscriptionId = $script:appSub
                properties = @{ securityRules = @(@{ name = 'r'; properties = @{ priority = 100; direction = 'Inbound'; access = 'Allow'; protocol = '*'; sourceAddressPrefix = $Source; destinationAddressPrefix = '*'; destinationPortRanges = @($Ports -split ',') } }) } }
        }
        $map = & $script:build @(
            & $nsg 'all' '*'
            & $nsg 'db' '1400-1500'
            & $nsg 'wide' '8000-9000'
            & $nsg 'web' '80,443'
            & $nsg 'inside' '*' 'VirtualNetwork'
        )
        $risk = { param([string] $Name) $n = & $script:node $map $Name; "$($n.risk)|$($n.rules[0].reason)" }
        & $risk 'all' | Should -Be 'high|Every port is open to the internet.'
        & $risk 'db' | Should -Be 'high|SQL Server (1433) open to the internet.'
        & $risk 'wide' | Should -Be 'medium|1,001 ports are open to the internet.'
        & $risk 'web' | Should -Be '|'
        & $risk 'inside' | Should -Be '|' -Because 'only what is open to the internet is flagged'
    }

    It 'reads a route table''s routes: each next hop resolved, a hop nothing has flagged, propagation' {
        $table = & $script:node $script:map 'rt-spoke'
        $default = $table.routes | Where-Object name -EQ 'default'
        & $script:short $default.target | Should -Be 'afw-hub'
        $default.targetName | Should -Be 'afw-hub'
        $default.risk | Should -BeNullOrEmpty
        $onPrem = $table.routes | Where-Object name -EQ 'to-onprem'
        $onPrem.risk | Should -Be 'high'
        $onPrem.reason | Should -BeLike 'No resource you can see has 10.0.1.9.*192.168.0.0/16*dropped*'
        $table.propagation | Should -Be 'off'
        $table.risk | Should -Be 'high'
        $script:map.Stats.Flagged | Should -Be 3
    }

    It 'flags 0.0.0.0/0 straight to the internet' {
        $row = @{ id = "/subscriptions/$script:appSub/resourceGroups/rg-x/providers/Microsoft.Network/routeTables/rt-open"; name = 'rt-open'; type = 'Microsoft.Network/routeTables'; resourceGroup = 'rg-x'; subscriptionId = $script:appSub
            properties = @{ routes = @(@{ name = 'out'; properties = @{ addressPrefix = '0.0.0.0/0'; nextHopType = 'Internet' } }, @{ name = 'sink'; properties = @{ addressPrefix = '10.9.0.0/16'; nextHopType = 'None' } }) } }
        $table = & $script:node (& $script:build @($row)) 'rt-open'
        $table.risk | Should -Be 'medium'
        ($table.routes | Where-Object name -EQ 'sink').reason | Should -BeLike '*dropped on purpose*'
        $table.propagation | Should -Be 'on'
    }

    It 'folds a private endpoint''s own network interface into the endpoint' {
        & $script:node $script:map 'pe-sql.nic' | Should -BeNullOrEmpty
        (& $script:node $script:map 'pe-sql').facts | Should -Contain '10.1.2.4'
        (& $script:node $script:map 'pe-sql').typeLabel | Should -Be 'Private Endpoint'
    }

    It 'flags what is attached to nothing' {
        (& $script:node $script:map 'disk-old-data').orphan | Should -Be 'unattached disk'
        (& $script:node $script:map 'nic-leftover').orphan | Should -BeLike 'not attached*'
        (& $script:node $script:map 'nsg-unused').orphan | Should -Be 'on no subnet or NIC'
        (& $script:node $script:map 'nsg-web').orphan | Should -BeNullOrEmpty
        (& $script:node $script:map 'nic-web-01').orphan | Should -BeNullOrEmpty
        $script:map.Stats.Orphans | Should -Be 3
    }

    It 'labels each resource with its product and a detail worth seeing' {
        $vm = & $script:node $script:map 'vm-web-01'
        $vm.typeLabel | Should -Be 'Virtual Machine'
        $vm.icon | Should -Be 'vm'
        $vm.facts | Should -Be @('Standard_D4s_v5', 'Linux')
        (& $script:node $script:map 'pip-web-02').facts | Should -Be @('51.140.1.20')
        (& $script:node $script:map 'kv-orders').typeLabel | Should -Be 'Key Vault'
        (& $script:node $script:map 'vm-web-01_OsDisk').facts | Should -Be @('64 GB', 'Premium_LRS')
    }

    It 'draws a resource outside the selection in its own resource group, marked as outside' {
        $spoke = @($script:estate | Where-Object { $_.resourceGroup -eq 'rg-spoke-app' })
        $hubVnet = @($script:estate | Where-Object { $_.id -like '*/virtualNetworks/vnet-hub' })
        $map = & $script:build $spoke $hubVnet
        $group = $map.Clusters | Where-Object { $_.kind -eq 'resourcegroup' -and $_.name -eq 'rg-hub' }
        $group.external | Should -BeTrue
        $group.detail | Should -Contain 'outside the selection'
        ($map.Clusters | Where-Object { $_.name -eq 'vnet-hub' }).external | Should -BeTrue
        (& $script:edge $map 'peering' 'vnet-spoke-app' 'vnet-hub').Count | Should -Be 1
        ($map.Clusters | Where-Object { $_.kind -eq 'resourcegroup' -and $_.name -eq 'rg-spoke-app' }).external | Should -BeFalse
        $map.Stats.Groups | Should -Be 1
    }

    It 'leaves out VM extensions and DNS link rows, and any -ExcludeType' {
        $map = & $script:build $script:estate @() @('microsoft.insights/*', 'microsoft.compute/disks')
        & $script:node $map 'appi-orders' | Should -BeNullOrEmpty
        & $script:node $map 'disk-old-data' | Should -BeNullOrEmpty
        & $script:node $map 'link-hub' | Should -BeNullOrEmpty
        & $script:node $map 'vm-web-01' | Should -Not -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - resource map page' {
    It 'writes one self-contained page: the map, ELK and only the icons it uses' {
        $path = Join-Path -Path $TestDrive -ChildPath 'map/estate.html'
        InModuleScope 'Azure.Admin.Console' -Parameters @{ Map = $script:map; Path = $path } {
            param($Map, $Path)
            Write-AACResourceMapHtml -Map $Map -Path $Path -Title 'Map </script> & more' -Fact @('29 resources') -Direction DOWN -Theme light -NsgView cards
        }
        $html = Get-Content -LiteralPath $path -Raw
        $html | Should -BeLike '*<title>Map &lt;/script&gt; &amp; more</title>*'
        $html | Should -BeLike '*function ELK*' -Because 'elkjs is inline'
        $html | Should -Not -BeLike '*/*AAC:*' -Because 'every placeholder is filled'
        $json = [regex]::Match($html, '<script id="aac-map" type="application/json">(.*?)</script>', 'Singleline').Groups[1].Value
        $json | Should -Not -BeLike '*</*' -Because "'</' would end the script element"
        $model = $json | ConvertFrom-Json
        $model.options.direction | Should -Be 'DOWN'
        $model.options.theme | Should -Be 'light'
        $model.options.nsgView | Should -Be 'cards'
        @($model.icons.PSObject.Properties.Name) | Should -Contain 'nsg' -Because 'chips always need the NSG and route table icons'
        @($model.icons.PSObject.Properties.Name) | Should -Contain 'routetable'
        $model.title | Should -Be 'Map </script> & more'
        $model.nodes.Count | Should -Be $script:map.Nodes.Count
        $model.edges.Count | Should -Be $script:map.Edges.Count
        @($model.icons.PSObject.Properties.Name) | Should -Contain 'vm'
        @($model.icons.PSObject.Properties.Name) | Should -Not -Contain 'iothub' -Because 'only the icons the map uses are embedded'
        $model.icons.vm.svg | Should -BeLike '<svg*'
    }

    It 'refuses a layout library that isn''t the one released with the module' {
        InModuleScope 'Azure.Admin.Console' {
            $saved = $script:AACResourceMapAsset
            try {
                $script:AACResourceMapAsset = $null
                Mock Get-FileHash { [pscustomobject]@{ Hash = 'BAD' } }
                { Get-AACResourceMapAsset } | Should -Throw '*refused lib/*SHA-256*'
            }
            finally { $script:AACResourceMapAsset = $saved }
        }
    }
}

Describe 'Azure Admin Console - Show-AACResourceMap' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { & $script:graphBatchShim $Query $SubscriptionId $ManagementGroupId $AsObject $AllowFailure }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -MockWith { }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -MockWith {
            $query = ($Body | ConvertFrom-Json).query
            $data = if ($query -match 'subscriptions/resourcegroups') {
                @(@{ name = 'rg-hub'; subscriptionId = $script:hubSub }, @{ name = 'rg-spoke-app'; subscriptionId = $script:appSub }) | Where-Object { $query -match "'$($_.name)'" }
            }
            elseif ($query -match "type =~ 'microsoft.resources/subscriptions'") {
                @(@{ subscriptionId = $script:hubSub; name = 'Contoso Connectivity' }, @{ subscriptionId = $script:appSub; name = 'Contoso Apps' })
            }
            elseif ($query -match 'properties contains') {
                @($script:estate | Where-Object { $row = $_; ($row.properties | ConvertTo-Json -Depth 20 -Compress) -match '"privateIPAddress":"10\.0\.1\.4"' -and $query -match '10\.0\.1\.4' -and $query -match [regex]::Escape($row.type.ToLowerInvariant()) })
            }
            elseif ($query -match 'id in~') {
                @($script:estate | Where-Object { $query -match [regex]::Escape("'$($_.id.ToLowerInvariant())'") -or $query -match [regex]::Escape("'$($_.id)'") })
            }
            else {
                @($script:estate | Where-Object { $query -match "'$($_.resourceGroup)'" })
            }
            @{ data = @($data) }
        }
    }

    It 'maps the resource groups, writes the page and opens it in the browser' {
        $path = Join-Path -Path $TestDrive -ChildPath 'estate.html'
        $result = Show-AACResourceMap -ResourceGroupName 'rg-hub', 'rg-spoke-app' -HtmlPath $path -PassThru
        Test-Path -LiteralPath $path | Should -BeTrue
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 1 -Exactly -ParameterFilter { $Path -eq $path }
        $result.PSObject.TypeNames | Should -Contain 'AAC.ResourceMap'
        $result.Path | Should -Be $path
        $result.Stats.Resources | Should -Be 30 -Because 'the private endpoint''s own NIC is folded into it'
        $result.Stats.Outside | Should -Be 0
        @($result.Nodes | Where-Object Orphan).Name | Sort-Object | Should -Be @('disk-old-data', 'nic-leftover', 'nsg-unused')
        @($result.Edges | Where-Object Kind -EQ 'route').Label | Sort-Object | Should -Be @('0.0.0.0/0 -> 10.0.1.4', '0.0.0.0/0 via rt-spoke') -Because 'the route table''s line for cards, the subnet''s for chips'
    }

    It 'brings in what a chosen resource group uses from outside it' {
        $result = Show-AACResourceMap -ResourceGroupName 'rg-spoke-app' -HtmlPath (Join-Path $TestDrive 'spoke.html') -NoBrowser -PassThru
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Open-AACFile -Times 0 -Exactly
        $result.Stats.Resources | Should -Be 23
        @($result.Clusters | Where-Object { $_.kind -eq 'vnet' -and $_.external }).name | Should -Be @('vnet-hub')
        @($result.Edges | Where-Object Kind -EQ 'peering').Count | Should -Be 1
        # rt-spoke's next hop, 10.0.1.4, is the hub's firewall: looked up, drawn outside.
        ($result.Nodes | Where-Object Name -EQ 'afw-hub').Outside | Should -BeTrue
        @($result.Edges | Where-Object { $_.Kind -eq 'route' -and $_.Label -eq '0.0.0.0/0 via rt-spoke' }).Count | Should -Be 1
        ($result.Nodes | Where-Object Name -EQ 'rt-spoke').Routes.Count | Should -Be 2
    }

    It 'asks the subscriptions it is given, and names the map after the resource groups' {
        $result = Show-AACResourceMap -SubscriptionId $script:appSub -ResourceGroupName 'rg-spoke-app' -HtmlPath (Join-Path $TestDrive 'sub.html') -NoBrowser -PassThru
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmRequest -ParameterFilter { $b = $Body | ConvertFrom-Json; $b.query -match '^resources' -and @($b.subscriptions) -contains $script:appSub }
        $result.Title | Should -Be 'Resource map: rg-spoke-app'
    }

    It 'warns about a resource group it can''t find, and stops when it finds none' {
        $null = Show-AACResourceMap -ResourceGroupName 'rg-spoke-app', 'rg-typo' -HtmlPath (Join-Path $TestDrive 'w.html') -NoBrowser -WarningVariable warnings -WarningAction SilentlyContinue
        "$warnings" | Should -BeLike "*No resource group named 'rg-typo'*"
        { Show-AACResourceMap -ResourceGroupName 'rg-nope' -NoBrowser } | Should -Throw "*No resource group named 'rg-nope' was found*"
    }

    It 'needs a subscription or a resource group to map' {
        { Show-AACResourceMap -NoBrowser } | Should -Throw '*-SubscriptionId, -ResourceGroupName, or both*'
    }
}
