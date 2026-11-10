<#
    Unit tests for New-AACDesignDiagram: a hub and spoke design planned from its
    parameters - subnets and their ranges, names, routes through the firewall,
    peerings, private endpoints - and drawn as draw.io. Nothing is read from Azure.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:draw = {
        param([hashtable] $With = @{})
        $file = Join-Path -Path $TestDrive -ChildPath "design-$([guid]::NewGuid().ToString('n').Substring(0, 6)).drawio"
        $p = @{ Name = 'contoso'; Spoke = 'orders'; Resource = 'FunctionApp', 'StorageAccount'; Firewall = $true; Path = $file; NoDisplay = $true }
        foreach ($key in $With.Keys) { $p[$key] = $With[$key] }
        $rows = @(New-AACDesignDiagram @p)
        @{ Rows = $rows; File = $p.Path; Xml = $(if (Test-Path -LiteralPath $p.Path) { [xml](Get-Content -LiteralPath $p.Path -Raw) } else { $null }); Text = $(if (Test-Path -LiteralPath $p.Path) { Get-Content -LiteralPath $p.Path -Raw } else { '' }) }
    }
    $script:subnet = { param($From, [string] $Network, [string] $Subnet) @($From.Rows | Where-Object { $_.VirtualNetwork -eq $Network -and $_.Subnet -eq $Subnet })[0] }
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 200
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - planning a hub and spoke design' {
    It 'carves each network''s subnets at their recommended size, in address order' {
        $d = & $script:draw @{ Bastion = $true; VpnGateway = $true; Resource = 'FunctionApp', 'StorageAccount', 'VirtualMachine' }
        @($d.Rows | Where-Object VirtualNetwork -EQ 'vnet-hub-prod-weu' | ForEach-Object { "$($_.Subnet) $($_.AddressPrefix)" }) | Should -Be @('AzureFirewallSubnet 10.0.0.0/26', 'AzureBastionSubnet 10.0.0.64/26', 'GatewaySubnet 10.0.0.128/27')
        @($d.Rows | Where-Object VirtualNetwork -EQ 'vnet-orders-prod-weu' | ForEach-Object { "$($_.Subnet) $($_.AddressPrefix)" }) | Should -Be @('snet-workload 10.1.0.0/24', 'snet-integration 10.1.1.0/26', 'snet-privateendpoints 10.1.1.64/26')
        (& $script:subnet $d 'vnet-orders-prod-weu' 'snet-workload').Usable | Should -Be 251 -Because 'Azure keeps five addresses of every subnet'
    }

    It 'routes the spokes through the firewall''s private IP' {
        $d = & $script:draw
        $row = & $script:subnet $d 'vnet-orders-prod-weu' 'snet-integration'
        "$($row.RouteTable) $($row.NextHop)" | Should -Be 'rt-orders-prod-weu 10.0.0.4' -Because 'the firewall takes the first address Azure leaves free'
        (& $script:subnet $d 'vnet-orders-prod-weu' 'snet-privateendpoints').RouteTable | Should -Be '' -Because 'private endpoints need no route table'
        (& $script:draw @{ Firewall = $false }).Rows | Where-Object RouteTable | Should -BeNullOrEmpty
    }

    It 'gives each spoke the next /16, and keeps the ranges given' {
        $d = & $script:draw @{ Spoke = 'orders', @{ Name = 'web'; AddressSpace = '10.50.0.0/20'; Resources = 'WebApp' }, 'data' }
        @($d.Rows | ForEach-Object { "$($_.VirtualNetwork) $($_.AddressSpace)" } | Select-Object -Unique | Where-Object { $_ -notlike 'vnet-hub*' }) | Should -Be @('vnet-orders-prod-weu 10.1.0.0/16', 'vnet-web-prod-weu 10.50.0.0/20', 'vnet-data-prod-weu 10.3.0.0/16')
    }

    It 'falls back to the smallest supported sizes when the space is tight, and refuses when even those don''t fit' {
        $d = & $script:draw @{ Spoke = @(@{ Name = 'tiny'; AddressSpace = '10.9.0.0/26'; Resources = 'WebApp', 'KeyVault' }) }
        @($d.Rows | Where-Object VirtualNetwork -EQ 'vnet-tiny-prod-weu' | ForEach-Object AddressPrefix) | Should -Be @('10.9.0.0/28', '10.9.0.16/28')
        { & $script:draw @{ Spoke = @(@{ Name = 'tiny'; AddressSpace = '10.9.0.0/29'; Resources = 'WebApp', 'KeyVault' }) } } | Should -Throw "*can't fit vnet-tiny-prod-weu's subnets*larger address space*"
        { & $script:draw @{ HubAddressSpace = '10.0.0.0/27' } } | Should -Throw '*AzureFirewallSubnet*'
    }

    It 'refuses networks that overlap, and ranges that aren''t ranges' {
        { & $script:draw @{ Spoke = @(@{ Name = 'clash'; AddressSpace = '10.0.2.0/24'; Resources = 'WebApp' }) } } | Should -Throw '*overlaps vnet-hub-prod-weu (10.0.0.0/22)*'
        { & $script:draw @{ Spoke = @(@{ Name = 'odd'; AddressSpace = '10.1.0.7/24'; Resources = 'WebApp' }) } } | Should -Throw "*doesn't start on a /24 boundary. Use 10.1.0.0/24*"
        { & $script:draw @{ HubAddressSpace = 'not-a-range' } } | Should -Throw '*give an IPv4 range*'
    }

    It 'keeps the subnets you give, and checks them' {
        $spoke = @{ Name = 'orders'; AddressSpace = '10.20.0.0/22'; Subnets = @(@{ Name = 'snet-app'; AddressPrefix = '10.20.0.0/24'; Resources = 'FunctionApp' }, @{ Name = 'snet-pe'; AddressPrefix = '10.20.1.0/27'; Resources = 'StorageAccount' }) }
        $d = & $script:draw @{ Spoke = @($spoke) }
        @($d.Rows | Where-Object VirtualNetwork -EQ 'vnet-orders-prod-weu' | ForEach-Object { "$($_.Subnet) $($_.AddressPrefix)" }) | Should -Be @('snet-app 10.20.0.0/24', 'snet-pe 10.20.1.0/27')
        $outside = @{ Name = 'orders'; AddressSpace = '10.20.0.0/22'; Subnets = @(@{ Name = 'snet-app'; AddressPrefix = '10.30.0.0/24'; Resources = 'FunctionApp' }) }
        { & $script:draw @{ Spoke = @($outside) } } | Should -Throw "*isn't inside 10.20.0.0/22*"
        $overlap = @{ Name = 'orders'; AddressSpace = '10.20.0.0/22'; Subnets = @(@{ Name = 'a'; AddressPrefix = '10.20.0.0/24'; Resources = 'FunctionApp' }, @{ Name = 'b'; AddressPrefix = '10.20.0.128/25'; Resources = 'StorageAccount' }) }
        { & $script:draw @{ Spoke = @($overlap) } } | Should -Throw '*their ranges overlap*'
        $nowhere = @{ Name = 'orders'; AddressSpace = '10.20.0.0/22'; Resources = 'FunctionApp', 'KeyVault'; Subnets = @(@{ Name = 'a'; AddressPrefix = '10.20.0.0/24'; Resources = 'FunctionApp' }) }
        { & $script:draw @{ Spoke = @($nowhere) } } | Should -Throw "*nowhere to put spoke 'orders''s KeyVault*"
    }

    It 'names everything, reaches each resource its own way, and lists them' {
        $d = & $script:draw @{ Resource = 'FunctionApp', 'StorageAccount', 'ApplicationGateway', 'StorageAccount' }
        $resources = @(New-AACDesignDiagram -Name contoso -Spoke orders -Resource FunctionApp, StorageAccount, ApplicationGateway, StorageAccount -Firewall -Path (Join-Path $TestDrive 'r.drawio') -NoDisplay -PassThru)
        $model = InModuleScope 'Azure.Admin.Console' { ConvertTo-AACDesignNetwork -Name c -Region westeurope -Environment prod -Hub @{ AddressSpace = '10.0.0.0/22'; Subscription = 's'; ResourceGroup = 'rg-hub'; Firewall = $true; Bastion = $false; VpnGateway = $false } -Spoke @(@{ Name = 'orders'; AddressSpace = '10.1.0.0/16'; Resources = @('FunctionApp', 'StorageAccount', 'ApplicationGateway', 'StorageAccount'); Subscription = 'sub-orders'; ResourceGroup = 'rg-orders'; Subnets = @() }) }
        @($model.Resources | ForEach-Object { "$($_.Name): $($_.Access)" }) | Should -Be @(
            'afw-hub-prod-weu: Private IP 10.0.0.4'
            'func-orders-prod-weu: VNet integration through snet-integration'
            'stordersprodweu: Private endpoint in snet-privateendpoints'
            'agw-orders-prod-weu: In snet-appgw'
            'stordersprodweu-02: Private endpoint in snet-privateendpoints'
        )
        $resources.Count | Should -BeGreaterThan 0
        @($model.Map.Nodes | Where-Object type -EQ 'Microsoft.Network/privateDnsZones').name | Should -Be @('privatelink.blob.core.windows.net') -Because 'one zone however many storage accounts'
    }
}

Describe 'Azure Admin Console - the design as draw.io' {
    It 'draws the subscription, resource group, network and subnet boxes with their names and ranges' {
        $d = & $script:draw @{ Bastion = $true }
        $d.Xml | Should -Not -BeNullOrEmpty -Because 'the file is valid XML'
        $kinds = @($d.Xml.SelectNodes('//object[@aacKind]') | ForEach-Object { $_.aacKind } | Select-Object -Unique)
        foreach ($kind in 'subscription', 'region', 'resourcegroup', 'vnet', 'subnet') { $kinds | Should -Contain $kind }
        foreach ($expected in 'sub-connectivity', 'sub-orders-prod', 'rg-hub-network-prod-weu', 'rg-orders-prod-weu', 'vnet-hub-prod-weu', '10.0.0.0/22', 'AzureFirewallSubnet', '10.0.0.0/26', 'snet-integration', '10.1.0.0/26', 'afw-hub-prod-weu', 'func-orders-prod-weu', 'stordersprodweu') {
            $d.Text | Should -Match ([regex]::Escape($expected)) -Because "the diagram shows $expected"
        }
        @($d.Xml.SelectNodes('//diagram') | ForEach-Object name) | Should -Contain 'Legend'
    }

    It 'connects the spokes to the hub, the routes to the firewall and the private endpoints to their services' {
        $d = & $script:draw @{ Spoke = 'orders', 'payments' }
        $labels = @($d.Xml.SelectNodes('//mxCell[@edge="1"]') | ForEach-Object value)
        @($labels | Where-Object { $_ -eq 'peering' }).Count | Should -Be 2
        @($labels | Where-Object { $_ -eq '0.0.0.0/0 next hop 10.0.0.4' }).Count | Should -Be 2
        $labels | Should -Contain 'private link'
        $labels | Should -Contain 'VNet integration'
        $vpn = & $script:draw @{ VpnGateway = $true }
        @($vpn.Xml.SelectNodes('//mxCell[@edge="1"]') | ForEach-Object value) | Should -Contain 'site-to-site VPN'
        @($vpn.Xml.SelectNodes('//mxCell[@edge="1"]') | ForEach-Object value) | Should -Contain 'peering, gateway transit'
    }

    It 'won''t replace a file unless asked, and keeps your changes with -Update' {
        $file = Join-Path $TestDrive 'kept.drawio'
        $null = New-AACDesignDiagram -Name contoso -Spoke orders -Resource WebApp -Path $file -NoDisplay
        { New-AACDesignDiagram -Name contoso -Spoke orders -Resource WebApp -Path $file -NoDisplay } | Should -Throw '*already exists. Use -Update*'
        $mine = (Get-Content -LiteralPath $file -Raw).Replace('</root>', '<mxCell id="my-note" value="My note" style="text;" vertex="1" parent="1"><mxGeometry x="10" y="10" width="80" height="20" as="geometry"/></mxCell></root>')
        [System.IO.File]::WriteAllText($file, $mine)
        $null = New-AACDesignDiagram -Name contoso -Spoke orders -Resource WebApp, KeyVault -Path $file -NoDisplay -Update
        $text = Get-Content -LiteralPath $file -Raw
        $text | Should -Match 'My note' -Because 'your own shapes are kept'
        $text | Should -Match 'kvordersprodweu|kv-orders-prod-weu'
        { New-AACDesignDiagram -Name contoso -Spoke orders -Path (Join-Path $TestDrive 'x.png') -NoDisplay } | Should -Throw '*ending in .drawio*'
    }

    It 'shows the address plan at the prompt and writes it to CSV' {
        $csv = Join-Path $TestDrive 'plan.csv'
        $text = (& $script:capture { New-AACDesignDiagram -Name contoso -Spoke orders -Resource FunctionApp, StorageAccount -Firewall -Path (Join-Path $TestDrive 'view.drawio') -NoPaging }).Text
        foreach ($expected in 'Address plan', 'snet-integration', '10.1.0.0/26', 'rt-orders-prod-weu') { $text | Should -Match ([regex]::Escape($expected)) }
        $null = & $script:capture { New-AACDesignDiagram -Name contoso -Spoke orders -Resource FunctionApp, StorageAccount -Firewall -Path (Join-Path $TestDrive 'csv.drawio') -CsvPath $csv }
        @(Import-Csv -LiteralPath $csv).AddressPrefix | Should -Contain '10.0.0.0/26'
    }

    It 'says which spoke settings and resources it doesn''t know' {
        { & $script:draw @{ Spoke = @(@{ Name = 'x'; Vnet = 'y' }) } } | Should -Throw "*doesn't know the spoke setting(s) Vnet*"
        { & $script:draw @{ Spoke = @(@{ Name = 'x'; Resources = 'Toaster' }) } } | Should -Throw "*doesn't know the resource 'Toaster'*"
        { & $script:draw @{ Spoke = 'orders', 'orders' } } | Should -Throw '*a name of its own*'
    }

    It 'draws the network for a design from New-AACArchitectureDesign: its region, firewall and the components it has a place for' {
        $design = [pscustomobject]@{
            PSTypeName = 'AAC.ArchitectureDesign'; Name = 'Contoso Orders'; Regions = @('northeurope', 'westeurope')
            Nodes      = @(
                [pscustomobject]@{ Id = 'hub'; Name = 'Hub virtual network'; Service = 'Microsoft.Network/virtualNetworks'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'firewall'; Name = 'Azure Firewall'; Service = 'Microsoft.Network/azureFirewalls'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'compute'; Name = 'App Service'; Service = 'Microsoft.Web/sites'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'worker'; Name = 'Worker (Functions)'; Service = 'Microsoft.Web/sites (functionapp)'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'data'; Name = 'Azure SQL Database'; Service = 'Microsoft.Sql/servers/databases'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'kv'; Name = 'Key Vault'; Service = 'Microsoft.KeyVault/vaults'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'edge'; Name = 'Front Door Premium'; Service = 'Microsoft.Cdn/profiles'; Region = 'northeurope' }
                [pscustomobject]@{ Id = 'compute-2'; Name = 'App Service'; Service = 'Microsoft.Web/sites'; Region = 'westeurope' }
            )
        }
        $file = Join-Path -Path $TestDrive -ChildPath 'from-design.drawio'
        $rows = @($design | New-AACDesignDiagram -Path $file -NoDisplay -WarningVariable seen -WarningAction SilentlyContinue)
        $text = Get-Content -LiteralPath $file -Raw

        foreach ($expected in 'contoso-orders - hub and spoke design', 'afw-hub-prod-neu', 'app-workload-prod-neu', 'func-workload-prod-neu', 'sql-workload-prod-neu', 'kv-workload-prod-neu') {
            $text | Should -Match ([regex]::Escape($expected)) -Because "the diagram shows $expected"
        }
        $text | Should -Not -Match '-prod-weu' -Because 'only the first region is drawn'
        @($rows | Where-Object Subnet -EQ 'AzureFirewallSubnet').Count | Should -Be 1 -Because 'the design has a firewall'
        "$seen" | Should -BeLike '*Front Door Premium*New-AACArchitectureDiagram*'
    }

    It 'reads a saved design file, and says what it needs without -Name, -Spoke or a real design' {
        $saved = Join-Path -Path $TestDrive -ChildPath 'design.json'
        @{ Name = 'files'; Regions = @('westeurope'); Nodes = @(@{ Name = 'Storage account'; Service = 'Microsoft.Storage/storageAccounts'; Region = 'westeurope' }) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $saved
        $rows = @(New-AACDesignDiagram -Design $saved -Spoke data -Path (Join-Path -Path $TestDrive -ChildPath 'files.drawio') -NoDisplay)
        @($rows | Where-Object VirtualNetwork -Like 'vnet-data-*').Count | Should -BeGreaterThan 0
        { New-AACDesignDiagram -Spoke orders -Path (Join-Path -Path $TestDrive -ChildPath 'n.drawio') } | Should -Throw '*needs -Name*'
        { New-AACDesignDiagram -Name x -Path (Join-Path -Path $TestDrive -ChildPath 'n.drawio') } | Should -Throw '*needs -Spoke*'
        { New-AACDesignDiagram -Design ([pscustomobject]@{ Name = 'x' }) -Path (Join-Path -Path $TestDrive -ChildPath 'n.drawio') } | Should -Throw '*with its Nodes*'
    }
}
