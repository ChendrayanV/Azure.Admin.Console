<#
    A made-up Contoso network for the Invoke-AACVirtualNetworkAssessment
    tests, as Azure Resource Graph rows. Each finding occurs at least once:

      vnet-hub-weu    sub-connectivity, 10.0.0.0/22, hub (VPN gateway, Azure Firewall, Bastion)
        GatewaySubnet       10.0.0.0/28 - smaller than /27, an NSG on it, a 0.0.0.0/0 route
        AzureFirewallSubnet 10.0.0.64/26
        AzureBastionSubnet  10.0.0.128/27 - smaller than /26
        snet-dns            10.0.1.0/28 - empty, no NSG
        peerings            vnet-spoke-app (Connected, gateway transit), vnet-spoke-old
                            (Initiated: no peering back), vnet-hub-eus (in a subscription
                            the account can't read)
        one custom DNS server; public IPs without DDoS; a VNet flow log; VpnGw1 (not AZ)
      vnet-spoke-app  sub-landingzone-app, 10.1.0.0/24, spoke
        snet-web    10.1.0.0/27 - 24 of 27 used; nsg-web (RDP from the internet);
                    a VM with a public IP; default outbound access
        snet-app    10.1.0.32/27 - 0.0.0.0/0 to the firewall; nsg-app; a NIC in asg-app
        snet-pe     10.1.0.64/28 - two private endpoints, no NSG, network policies off;
                    blob's zone linked, the vault's not (and its connection Pending)
        snet-full   10.1.0.80/29 - full; a private subnet
        peering     to the hub: remote gateways without forwarded traffic, LocalNotInSync
        Azure DNS; an NSG flow log only; encryption off
      vnet-spoke-old  sub-landingzone-app, 10.1.0.0/21 - overlaps vnet-spoke-app; unused
        snet-legacy 10.1.1.0/24, snet-big 10.1.4.0/22 - empty, no NSG, oversized
      asg-db named by an nsg-app rule with no NIC in it; asg-orphan unused

    Returns @{ SubscriptionId; Rows (Resource Graph query name -> rows);
    Converter (ConvertTo-AACVirtualNetworkAssessment's parameters) }.
#>
function Get-AACContosoNetwork {
    $hubSub = '11111111-1111-1111-1111-111111111111'
    $appSub = '22222222-2222-2222-2222-222222222222'
    $farSub = '33333333-3333-3333-3333-333333333333'
    $id = { param([string] $Sub, [string] $Group, [string] $Type, [string] $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/Microsoft.Network/$Type/$Name" }
    $hub = & $id $hubSub 'rg-hub' 'virtualNetworks' 'vnet-hub-weu'
    $app = & $id $appSub 'rg-app' 'virtualNetworks' 'vnet-spoke-app'
    $old = & $id $appSub 'rg-legacy' 'virtualNetworks' 'vnet-spoke-old'
    $far = & $id $farSub 'rg-hub-eus' 'virtualNetworks' 'vnet-hub-eus'
    $nsg = @{ gw = (& $id $hubSub 'rg-hub' 'networkSecurityGroups' 'nsg-gw'); web = (& $id $appSub 'rg-app' 'networkSecurityGroups' 'nsg-web'); app = (& $id $appSub 'rg-app' 'networkSecurityGroups' 'nsg-app') }
    $asg = @{ app = (& $id $appSub 'rg-app' 'applicationSecurityGroups' 'asg-app'); db = (& $id $appSub 'rg-app' 'applicationSecurityGroups' 'asg-db'); orphan = (& $id $appSub 'rg-app' 'applicationSecurityGroups' 'asg-orphan') }
    $rt = @{ gw = (& $id $hubSub 'rg-hub' 'routeTables' 'rt-gw'); spoke = (& $id $appSub 'rg-app' 'routeTables' 'rt-spoke') }
    $pip = { param([string] $Sub, [string] $Group, [string] $Name) & $id $Sub $Group 'publicIPAddresses' $Name }
    $ipConfig = { param([string] $Owner, [int] $Count = 1) @(1..$Count | ForEach-Object { @{ id = "$Owner/ipConfigurations/ipconfig$_" } }) }
    $subnet = {
        param([string] $Vnet, [string] $Name, [string] $Prefix, [hashtable] $More = @{})
        $properties = @{ addressPrefix = $Prefix; provisioningState = 'Succeeded' }
        foreach ($key in $More.Keys) { $properties[$key] = $More[$key] }
        @{ id = "$Vnet/subnets/$Name"; name = $Name; properties = $properties }
    }
    $peering = {
        param([string] $Name, [string] $Remote, [string[]] $RemoteSpace, [hashtable] $More = @{})
        $properties = @{ peeringState = 'Connected'; peeringSyncLevel = 'FullyInSync'; allowVirtualNetworkAccess = $true; allowForwardedTraffic = $true; allowGatewayTransit = $false; useRemoteGateways = $false; remoteVirtualNetwork = @{ id = $Remote }; remoteAddressSpace = @{ addressPrefixes = $RemoteSpace } }
        foreach ($key in $More.Keys) { $properties[$key] = $More[$key] }
        @{ name = $Name; properties = $properties }
    }
    $nicId = { param([string] $Sub, [string] $Group, [string] $Name) & $id $Sub $Group 'networkInterfaces' $Name }

    # --- vnet-hub-weu ----------------------------------------------------------------------------------------------
    $hubVnet = @{
        id = $hub; name = 'vnet-hub-weu'; resourceGroup = 'rg-hub'; subscriptionId = $hubSub; location = 'westeurope'; tags = @{ env = 'prod'; role = 'hub' }
        properties = @{
            provisioningState = 'Succeeded'; addressSpace = @{ addressPrefixes = @('10.0.0.0/22') }; dhcpOptions = @{ dnsServers = @('10.0.1.4') }
            enableDdosProtection = $false; encryption = @{ enabled = $false; enforcement = 'AllowUnencrypted' }
            subnets = @(
                & $subnet $hub 'GatewaySubnet' '10.0.0.0/28' @{ networkSecurityGroup = @{ id = $nsg.gw }; routeTable = @{ id = $rt.gw }; ipConfigurations = @(& $ipConfig (& $id $hubSub 'rg-hub' 'virtualNetworkGateways' 'vpngw-hub')) }
                & $subnet $hub 'AzureFirewallSubnet' '10.0.0.64/26' @{ ipConfigurations = @(& $ipConfig (& $id $hubSub 'rg-hub' 'azureFirewalls' 'afw-hub')) }
                & $subnet $hub 'AzureBastionSubnet' '10.0.0.128/27' @{ ipConfigurations = @(& $ipConfig (& $id $hubSub 'rg-hub' 'bastionHosts' 'bas-hub')) }
                & $subnet $hub 'snet-dns' '10.0.1.0/28'
            )
            virtualNetworkPeerings = @(
                & $peering 'hub-to-spoke-app' $app @('10.1.0.0/24') @{ allowGatewayTransit = $true }
                & $peering 'hub-to-spoke-old' $old @('10.1.0.0/21') @{ peeringState = 'Initiated' }
                & $peering 'hub-to-hub-eus' $far @('10.50.0.0/22')
            )
        }
    }

    # --- vnet-spoke-app --------------------------------------------------------------------------------------------
    $web = @(1..22 | ForEach-Object { @{ id = "$(& $nicId $appSub 'rg-app' "nic-scale-$_")/ipConfigurations/ipconfig1" } }) + @(& $ipConfig (& $nicId $appSub 'rg-app' 'nic-web-1')) + @(& $ipConfig (& $nicId $appSub 'rg-app' 'nic-web-2'))
    $appVnet = @{
        id = $app; name = 'vnet-spoke-app'; resourceGroup = 'rg-app'; subscriptionId = $appSub; location = 'westeurope'; tags = @{ env = 'prod' }
        properties = @{
            provisioningState = 'Succeeded'; addressSpace = @{ addressPrefixes = @('10.1.0.0/24') }; flowTimeoutInMinutes = 10
            subnets = @(
                & $subnet $app 'snet-web' '10.1.0.0/27' @{ networkSecurityGroup = @{ id = $nsg.web }; ipConfigurations = $web; serviceEndpoints = @(@{ service = 'Microsoft.Storage'; locations = @('westeurope') }) }
                & $subnet $app 'snet-app' '10.1.0.32/27' @{ networkSecurityGroup = @{ id = $nsg.app }; routeTable = @{ id = $rt.spoke }; ipConfigurations = @(& $ipConfig (& $nicId $appSub 'rg-app' 'nic-app-1')) }
                & $subnet $app 'snet-pe' '10.1.0.64/28' @{ privateEndpointNetworkPolicies = 'Disabled'; privateEndpoints = @(@{ id = 'pe-blob' }, @{ id = 'pe-vault' }); ipConfigurations = @(& $ipConfig (& $nicId $appSub 'rg-app' 'pe-blob.nic')) + @(& $ipConfig (& $nicId $appSub 'rg-app' 'pe-vault.nic')) }
                & $subnet $app 'snet-full' '10.1.0.80/29' @{ networkSecurityGroup = @{ id = $nsg.app }; defaultOutboundAccess = $false; ipConfigurations = @(1..3 | ForEach-Object { @{ id = "$(& $nicId $appSub 'rg-app' "nic-batch-$_")/ipConfigurations/ipconfig1" } }) }
            )
            virtualNetworkPeerings = @(
                & $peering 'spoke-app-to-hub' $hub @('10.0.0.0/22') @{ useRemoteGateways = $true; allowForwardedTraffic = $false; peeringSyncLevel = 'LocalNotInSync' }
            )
        }
    }

    # --- vnet-spoke-old --------------------------------------------------------------------------------------------
    $oldVnet = @{
        id = $old; name = 'vnet-spoke-old'; resourceGroup = 'rg-legacy'; subscriptionId = $appSub; location = 'westeurope'; tags = $null
        properties = @{
            provisioningState = 'Succeeded'; addressSpace = @{ addressPrefixes = @('10.1.0.0/21') }
            subnets = @(
                & $subnet $old 'snet-legacy' '10.1.1.0/24'
                & $subnet $old 'snet-big' '10.1.4.0/22'
            )
            virtualNetworkPeerings = @()
        }
    }

    # --- NICs, NSGs, ASGs, routes, endpoints ---------------------------------------------------------------------------
    $nic = {
        param([string] $Name, [string] $Subnet, [hashtable] $More = @{})
        $configuration = @{ name = 'ipconfig1'; properties = @{ privateIPAddress = $More['ip']; subnet = @{ id = $Subnet } } }
        if ($More['publicIp']) { $configuration.properties.publicIPAddress = @{ id = $More['publicIp'] } }
        if ($More['asgs']) { $configuration.properties.applicationSecurityGroups = @($More['asgs'] | ForEach-Object { @{ id = $_ } }) }
        @{
            id = & $nicId $appSub 'rg-app' $Name; name = $Name; resourceGroup = 'rg-app'; nsg = ''; vm = $(if ($More['vm']) { (& $id $appSub 'rg-app' 'virtualMachines' $More['vm']).Replace('Microsoft.Network', 'Microsoft.Compute').ToLowerInvariant() } else { '' })
            ipForwarding = $false; privateEndpoint = $(if ($More['pe']) { (& $id $appSub 'rg-app' 'privateEndpoints' $More['pe']).ToLowerInvariant() } else { '' }); ipConfigurations = @($configuration)
        }
    }
    $nics = @(
        & $nic 'nic-web-1' "$app/subnets/snet-web" @{ ip = '10.1.0.4'; vm = 'vm-web-1'; publicIp = (& $pip $appSub 'rg-app' 'pip-web-1') }
        & $nic 'nic-web-2' "$app/subnets/snet-web" @{ ip = '10.1.0.5'; vm = 'vm-web-2' }
        & $nic 'nic-app-1' "$app/subnets/snet-app" @{ ip = '10.1.0.36'; vm = 'vm-app-1'; asgs = @($asg.app) }
        & $nic 'pe-blob.nic' "$app/subnets/snet-pe" @{ ip = '10.1.0.68'; pe = 'pe-blob' }
        & $nic 'pe-vault.nic' "$app/subnets/snet-pe" @{ ip = '10.1.0.69'; pe = 'pe-vault' }
    )
    $rule = {
        param([string] $Name, [int] $Priority, [hashtable] $More)
        $properties = @{ priority = $Priority; direction = 'Inbound'; access = 'Allow'; protocol = 'Tcp'; sourceAddressPrefix = '*'; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = '*'; provisioningState = 'Succeeded' }
        foreach ($key in $More.Keys) { $properties[$key] = $More[$key] }
        @{ name = $Name; properties = $properties }
    }
    $nsgRow = {
        param([string] $Id, [string] $Sub, [object[]] $Rules, [string[]] $Subnets)
        @{ id = $Id; name = ($Id -split '/')[-1]; resourceGroup = ($Id -split '/')[4]; subscriptionId = $Sub; location = 'westeurope'; tags = @{}; properties = @{ securityRules = @($Rules); defaultSecurityRules = @(); subnets = @($Subnets | ForEach-Object { @{ id = $_ } }) } }
    }
    $nsgs = @(
        & $nsgRow $nsg.gw $hubSub @() @("$hub/subnets/GatewaySubnet")
        & $nsgRow $nsg.web $appSub @(& $rule 'allow-rdp-internet' 100 @{ sourceAddressPrefix = 'Internet'; destinationPortRange = '3389' }) @("$app/subnets/snet-web")
        & $nsgRow $nsg.app $appSub @(& $rule 'allow-app-to-db' 100 @{ sourceAddressPrefix = $null; destinationAddressPrefix = $null; destinationPortRange = '1433'; sourceApplicationSecurityGroups = @(@{ id = $asg.app }); destinationApplicationSecurityGroups = @(@{ id = $asg.db }) }) @("$app/subnets/snet-app", "$app/subnets/snet-full")
    )
    $asgs = @(foreach ($key in 'app', 'db', 'orphan') { @{ id = $asg[$key]; name = "asg-$key"; resourceGroup = 'rg-app'; location = 'westeurope' } })
    $toFirewall = @{ name = 'default-to-firewall'; properties = @{ addressPrefix = '0.0.0.0/0'; nextHopType = 'VirtualAppliance'; nextHopIpAddress = '10.0.0.68' } }
    $routeTables = @(
        @{ id = $rt.gw; name = 'rt-gw'; resourceGroup = 'rg-hub'; routes = @($toFirewall); disableBgpRoutePropagation = $false }
        @{ id = $rt.spoke; name = 'rt-spoke'; resourceGroup = 'rg-app'; routes = @($toFirewall); disableBgpRoutePropagation = $true }
    )
    $ipConfigurationOn = { param([string] $Subnet, [string] $PublicIp) @(@{ name = 'ipconfig1'; properties = @{ subnet = @{ id = $Subnet }; publicIPAddress = @{ id = $PublicIp } } }) }
    $gateways = @(@{ id = (& $id $hubSub 'rg-hub' 'virtualNetworkGateways' 'vpngw-hub'); name = 'vpngw-hub'; resourceGroup = 'rg-hub'; gatewayType = 'Vpn'; vpnType = 'RouteBased'; sku = 'VpnGw1'; activeActive = $false; enableBgp = $true; ipConfigurations = & $ipConfigurationOn "$hub/subnets/GatewaySubnet" (& $pip $hubSub 'rg-hub' 'pip-vpngw') })
    $firewalls = @(@{ id = (& $id $hubSub 'rg-hub' 'azureFirewalls' 'afw-hub'); name = 'afw-hub'; resourceGroup = 'rg-hub'; tier = 'Premium'; zones = @('1', '2', '3'); threatIntelMode = 'Deny'; ipConfigurations = & $ipConfigurationOn "$hub/subnets/AzureFirewallSubnet" (& $pip $hubSub 'rg-hub' 'pip-afw') })
    $bastions = @(@{ id = (& $id $hubSub 'rg-hub' 'bastionHosts' 'bas-hub'); name = 'bas-hub'; resourceGroup = 'rg-hub'; sku = 'Standard'; ipConfigurations = & $ipConfigurationOn "$hub/subnets/AzureBastionSubnet" (& $pip $hubSub 'rg-hub' 'pip-bas') })
    $publicIps = @(
        foreach ($item in @(@($appSub, 'rg-app', 'pip-web-1'), @($hubSub, 'rg-hub', 'pip-vpngw'), @($hubSub, 'rg-hub', 'pip-afw'), @($hubSub, 'rg-hub', 'pip-bas'))) {
            @{ id = & $pip $item[0] $item[1] $item[2]; name = $item[2]; ipAddress = '203.0.113.10'; sku = 'Standard'; protectionMode = 'VirtualNetworkInherited'; attachedTo = '' }
        }
    )
    $privateEndpoints = @(
        @{ id = (& $id $appSub 'rg-app' 'privateEndpoints' 'pe-blob'); name = 'pe-blob'; resourceGroup = 'rg-app'; subnet = "$app/subnets/snet-pe".ToLowerInvariant(); target = "/subscriptions/$appSub/resourceGroups/rg-app/providers/Microsoft.Storage/storageAccounts/stcontosoapp"; groupIds = @('blob'); status = 'Approved' }
        @{ id = (& $id $appSub 'rg-app' 'privateEndpoints' 'pe-vault'); name = 'pe-vault'; resourceGroup = 'rg-app'; subnet = "$app/subnets/snet-pe".ToLowerInvariant(); target = "/subscriptions/$appSub/resourceGroups/rg-app/providers/Microsoft.KeyVault/vaults/kv-contoso-app"; groupIds = @('vault'); status = 'Pending' }
    )
    $flowLogs = @(
        @{ id = "/subscriptions/$hubSub/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_westeurope/flowLogs/fl-hub"; name = 'fl-hub'; target = $hub.ToLowerInvariant(); enabled = $true; retentionEnabled = $true; retentionDays = 90; storageId = 'st'; analytics = $true; workspace = 'law'; interval = 10; version = 2 }
        @{ id = "/subscriptions/$appSub/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_westeurope/flowLogs/fl-nsg-web"; name = 'fl-nsg-web'; target = $nsg.web.ToLowerInvariant(); enabled = $true; retentionEnabled = $true; retentionDays = 30; storageId = 'st'; analytics = $false; workspace = ''; interval = 60; version = 2 }
    )
    $dnsLinks = @(@{ id = "/subscriptions/$hubSub/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net/virtualNetworkLinks/link-spoke-app"; zone = 'privatelink.blob.core.windows.net'; vnet = $app.ToLowerInvariant(); registration = $false; state = 'Completed' })
    $allVnets = @(foreach ($vnet in $hubVnet, $appVnet, $oldVnet) {
            @{ id = $vnet.id; name = $vnet.name; subscriptionId = $vnet.subscriptionId; location = $vnet.location; prefixes = $vnet.properties.addressSpace.addressPrefixes; peerings = $vnet.properties.virtualNetworkPeerings }
        })

    $rows = [ordered]@{
        subscriptions    = @(@{ subscriptionId = $hubSub; name = 'sub-connectivity' }, @{ subscriptionId = $appSub; name = 'sub-landingzone-app' })
        vnets            = @($hubVnet, $appVnet, $oldVnet)
        nics             = $nics
        nsgs             = $nsgs
        routeTables      = $routeTables
        natGateways      = @()
        asgs             = $asgs
        publicIps        = $publicIps
        privateEndpoints = $privateEndpoints
        flowLogs         = $flowLogs
        gateways         = $gateways
        firewalls        = $firewalls
        bastions         = $bastions
        dnsResolvers     = @()
        allVnets         = $allVnets
        dnsLinks         = $dnsLinks
    }
    $converter = @{
        VirtualNetwork = $rows.vnets
        AllNetwork = @(foreach ($vnet in $allVnets) { @{ id = $vnet.id; name = $vnet.name; subscriptionId = $vnet.subscriptionId; location = $vnet.location; prefixes = $vnet.prefixes; peers = @($vnet.peerings | ForEach-Object { $_.properties.remoteVirtualNetwork.id.ToLowerInvariant() }) } })
        NetworkInterface = $nics; RouteTable = $routeTables; ApplicationSecurityGroup = $asgs; PublicIp = $publicIps; PrivateEndpoint = $privateEndpoints; FlowLog = $flowLogs
        Firewall = $firewalls; Bastion = $bastions; Gateway = $gateways; DnsLink = $dnsLinks; NetworkSecurityGroup = $nsgs
        SubscriptionName = @{ $hubSub = 'sub-connectivity'; $appSub = 'sub-landingzone-app' }
    }
    @{ HubSubscriptionId = $hubSub; AppSubscriptionId = $appSub; Rows = $rows; Converter = $converter }
}
