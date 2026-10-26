<#
    A made-up Contoso estate for Get-AACIPAMReport: Azure Resource Graph
    rows (virtual networks with subnets and peerings, a Virtual WAN hub,
    network interfaces, scale set instances, a load balancer, a firewall, a
    gateway, private endpoints, public IPs) and an address plan.

    Built to hit every case:
      vnet-hub-weu     10.20.0.0/22   Corp / Azure-EU; gateway, firewall,
                                      two VMs and an unattached NIC
      vnet-spoke-app   10.20.4.0/22   snet-web 10.20.4.0/28 with 10 of 11
                                      usable addresses taken (Critical);
                                      private endpoints; a load balancer;
                                      the IPAM reservation tag
      vnet-spoke-dup   10.20.4.0/24   overlaps vnet-spoke-app - and is peered
                                      with it (High)
      vnet-legacy      10.20.200.0/24 overlaps the external London DC range
                                      (Medium)
      vhub-weu         10.20.250.0/24 a Virtual WAN hub in Azure-EU
      vnet-us          10.30.0.0/21   Corp / Azure-US; a scale set of three
      vnet-straddle    10.30.15.0/24 + 10.40.0.0/24 - partly in the plan
      vnet-rogue       192.168.50.0/24 in no block (Unmanaged)
      Lab / Lab-1      172.16.0.0/22  an unused block
#>

function Get-AACContosoIpam {
    $subA = 'aaaaaaaa-0000-0000-0000-00000000000a'
    $subB = 'bbbbbbbb-0000-0000-0000-00000000000b'
    $rgId = { param([string] $Sub, [string] $Rg) "/subscriptions/$Sub/resourceGroups/$Rg" }
    $vnetId = { param([string] $Sub, [string] $Name) "$(& $rgId $Sub 'rg-network')/providers/Microsoft.Network/virtualNetworks/$Name" }
    $nicConfig = { param([string] $NicId) "$NicId/ipConfigurations/ipconfig1" }
    $subnet = {
        param([string] $VnetId, [string] $Name, [string] $Prefix, [string[]] $ConfigIds = @(), [hashtable] $Extra = @{})
        $properties = @{ addressPrefix = $Prefix; ipConfigurations = @($ConfigIds | ForEach-Object { @{ id = $_ } }) }
        foreach ($k in $Extra.Keys) { $properties[$k] = $Extra[$k] }
        @{ id = "$VnetId/subnets/$Name"; name = $Name; properties = $properties }
    }
    $peering = { param([string] $Remote) @{ name = "to-$(($Remote -split '/')[-1])"; properties = @{ remoteVirtualNetwork = @{ id = $Remote }; peeringState = 'Connected' } } }
    $vnet = {
        param([string] $Sub, [string] $Name, [string[]] $Prefixes, [object[]] $Subnets, [string[]] $Peers = @(), [string[]] $Dns = @(), [hashtable] $Tags = @{})
        @{ id = (& $vnetId $Sub $Name); name = $Name; resourceGroup = 'rg-network'; subscriptionId = $Sub; location = 'westeurope'; tags = $Tags
            prefixes = $Prefixes; dnsServers = $Dns; subnets = $Subnets; peerings = @($Peers | ForEach-Object { & $peering $_ }) }
    }
    $nic = {
        param([string] $Sub, [string] $Name, [string] $Ip, [string] $Allocation = 'Dynamic', [string] $Vm = '', [string] $PrivateEndpoint = '', [string] $PublicIpId = '')
        $id = "$(& $rgId $Sub 'rg-app')/providers/Microsoft.Network/networkInterfaces/$Name"
        $config = @{ id = (& $nicConfig $id); properties = @{ privateIPAddress = $Ip; privateIPAllocationMethod = $Allocation } }
        if ($PublicIpId) { $config.properties.publicIPAddress = @{ id = $PublicIpId } }
        @{ id = $id; name = $Name; resourceGroup = 'rg-app'; subscriptionId = $Sub; vm = $Vm; privateEndpoint = $PrivateEndpoint; managedBy = ''; ipConfigurations = @($config) }
    }

    $hubId = & $vnetId $subA 'vnet-hub-weu'
    $appId = & $vnetId $subA 'vnet-spoke-app'
    $dupId = & $vnetId $subA 'vnet-spoke-dup'
    $vm = { param([string] $Name) "$(& $rgId $subA 'rg-app')/providers/Microsoft.Compute/virtualMachines/$Name" }
    $pip = "$(& $rgId $subA 'rg-app')/providers/Microsoft.Network/publicIPAddresses/pip-vm1"

    # Network interfaces: two VMs and an orphan in the hub, ten web servers, two private endpoints.
    $nics = [System.Collections.Generic.List[object]]::new()
    $nics.Add((& $nic $subA 'nic-vm1' '10.20.1.4' 'Static' (& $vm 'vm1') '' $pip))
    $nics.Add((& $nic $subA 'nic-vm2' '10.20.1.5' 'Dynamic' (& $vm 'vm2')))
    $nics.Add((& $nic $subA 'nic-orphan' '10.20.1.6'))
    foreach ($i in 1..10) { $nics.Add((& $nic $subA "nic-web$i" "10.20.4.$(3 + $i)" 'Dynamic' (& $vm "web$i"))) }
    $peSql = "$(& $rgId $subA 'rg-app')/providers/Microsoft.Network/privateEndpoints/pe-sql"
    $peKv = "$(& $rgId $subA 'rg-app')/providers/Microsoft.Network/privateEndpoints/pe-kv"
    $nics.Add((& $nic $subA 'pe-sql.nic' '10.20.5.4' 'Dynamic' '' $peSql))
    $nics.Add((& $nic $subA 'pe-kv.nic' '10.20.5.5' 'Dynamic' '' $peKv))
    $nicId = { param([string] $Name) @($nics | Where-Object { $_.name -eq $Name })[0].id }

    # A scale set of three in vnet-us.
    $usId = & $vnetId $subB 'vnet-us'
    $scaleSet = @(foreach ($n in 0..2) {
            $id = "$(& $rgId $subB 'rg-api')/providers/Microsoft.Compute/virtualMachineScaleSets/vmss-api/virtualMachines/$n/networkInterfaces/nic-api"
            @{ id = $id; resourceGroup = 'rg-api'; subscriptionId = $subB; ipConfigurations = @(@{ id = "$id/ipConfigurations/ipconfig1"; properties = @{ privateIPAddress = "10.30.0.$(4 + $n)"; privateIPAllocationMethod = 'Dynamic' } }) }
        })

    # A load balancer, a firewall and a gateway.
    $lbFrontend = "$(& $rgId $subA 'rg-app')/providers/Microsoft.Network/loadBalancers/lb-int/frontendIPConfigurations/fe-web"
    $fwConfig = "$(& $rgId $subA 'rg-network')/providers/Microsoft.Network/azureFirewalls/fw-hub/azureFirewallIpConfigurations/fw-config"
    $gwConfig = "$(& $rgId $subA 'rg-network')/providers/Microsoft.Network/virtualNetworkGateways/vpngw-hub/ipConfigurations/default"
    $ipResources = @(
        @{ id = ($lbFrontend -replace '/frontendIPConfigurations/.*$'); name = 'lb-int'; type = 'Microsoft.Network/loadBalancers'; resourceGroup = 'rg-app'; subscriptionId = $subA; configs = @(@{ id = $lbFrontend; properties = @{ privateIPAddress = '10.20.6.4'; privateIPAllocationMethod = 'Static' } }) }
        @{ id = ($fwConfig -replace '/azureFirewallIpConfigurations/.*$'); name = 'fw-hub'; type = 'Microsoft.Network/azureFirewalls'; resourceGroup = 'rg-network'; subscriptionId = $subA; configs = @(@{ id = $fwConfig; properties = @{ privateIPAddress = '10.20.0.68'; privateIPAllocationMethod = 'Dynamic' } }) }
        @{ id = ($gwConfig -replace '/ipConfigurations/.*$'); name = 'vpngw-hub'; type = 'Microsoft.Network/virtualNetworkGateways'; resourceGroup = 'rg-network'; subscriptionId = $subA; configs = @(@{ id = $gwConfig; properties = @{ privateIPAllocationMethod = 'Dynamic' } }) }
    )

    $vnets = @(
        (& $vnet $subA 'vnet-hub-weu' @('10.20.0.0/22') @(
                (& $subnet $hubId 'GatewaySubnet' '10.20.0.0/27' @($gwConfig))
                (& $subnet $hubId 'AzureFirewallSubnet' '10.20.0.64/26' @($fwConfig))
                (& $subnet $hubId 'snet-shared' '10.20.1.0/24' @((& $nicConfig (& $nicId 'nic-vm1')), (& $nicConfig (& $nicId 'nic-vm2')), (& $nicConfig (& $nicId 'nic-orphan'))))
            ) @($appId) @('10.20.1.4'))
        (& $vnet $subA 'vnet-spoke-app' @('10.20.4.0/22') @(
                (& $subnet $appId 'snet-web' '10.20.4.0/28' @(1..10 | ForEach-Object { & $nicConfig (& $nicId "nic-web$_") }))
                (& $subnet $appId 'snet-pe' '10.20.5.0/24' @((& $nicConfig (& $nicId 'pe-sql.nic')), (& $nicConfig (& $nicId 'pe-kv.nic'))))
                (& $subnet $appId 'snet-lb' '10.20.6.0/26' @($lbFrontend))
                (& $subnet $appId 'snet-func' '10.20.7.0/26' @() @{ delegations = @(@{ properties = @{ serviceName = 'Microsoft.Web/serverFarms' } }) })
            ) @($hubId, $dupId) @() @{ 'X-IPAM-RES-ID' = 'res-123' })
        (& $vnet $subA 'vnet-spoke-dup' @('10.20.4.0/24') @((& $subnet $dupId 'default' '10.20.4.0/24')) @($appId))
        (& $vnet $subA 'vnet-legacy' @('10.20.200.0/24') @((& $subnet (& $vnetId $subA 'vnet-legacy') 'default' '10.20.200.0/24')))
        (& $vnet $subB 'vnet-us' @('10.30.0.0/21') @((& $subnet $usId 'snet-vmss' '10.30.0.0/24' @($scaleSet | ForEach-Object { $_.ipConfigurations[0].id }))))
        (& $vnet $subB 'vnet-straddle' @('10.30.15.0/24', '10.40.0.0/24') @())
        (& $vnet $subB 'vnet-rogue' @('192.168.50.0/24') @() @() @() @{ 'X-IPAM-RES-ID' = 'res-999' })
    )
    $hubs = @(@{ id = "$(& $rgId $subA 'rg-vwan')/providers/Microsoft.Network/virtualHubs/vhub-weu"; name = 'vhub-weu'; resourceGroup = 'rg-vwan'; subscriptionId = $subA; location = 'westeurope'; prefix = '10.20.250.0/24'; vwan = "$(& $rgId $subA 'rg-vwan')/providers/Microsoft.Network/virtualWans/vwan-contoso" })

    @{
        Plan = @{
            Spaces   = @(
                @{ Name = 'Corp'; Description = 'Production address space'; Blocks = @(
                        @{ Name = 'Azure-EU'; Cidr = '10.20.0.0/16'; Description = 'West and North Europe' }
                        @{ Name = 'Azure-US'; Cidr = '10.30.0.0/20' }
                    )
                }
                @{ Name = 'Lab'; Blocks = @(@{ Name = 'Lab-1'; Cidr = '172.16.0.0/22' }) }
            )
            External = @(@{ Name = 'London DC'; Cidr = '10.20.200.0/22'; Description = 'On-premises, over ExpressRoute' })
        }
        Rows = @{
            vnets            = $vnets
            hubs             = $hubs
            nics             = $nics.ToArray()
            scaleSetNics     = $scaleSet
            ipResources      = $ipResources
            privateEndpoints = @(
                @{ id = $peSql; name = 'pe-sql'; target = "$(& $rgId $subA 'rg-data')/providers/Microsoft.Sql/servers/sql-prod" }
                @{ id = $peKv; name = 'pe-kv'; target = "$(& $rgId $subA 'rg-app')/providers/Microsoft.KeyVault/vaults/kv-app" }
            )
            publicIps        = @(@{ id = $pip; ipAddress = '20.50.1.10' })
            subscriptions    = @(@{ subscriptionId = $subA; name = 'Contoso Connectivity' }, @{ subscriptionId = $subB; name = 'Contoso US' })
        }
    }
}
