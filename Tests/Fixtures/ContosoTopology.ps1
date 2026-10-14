<#
    Made-up Contoso network topology for NetworkTopology.Tests.ps1: the
    hub-and-spoke estate of ContosoEstate.ps1, and around it:

      vnet-hub (Contoso Connectivity, uksouth)   firewall, gateway, Bastion,
                                                 and vm-nva, whose NIC forwards IP traffic
        <-> vnet-spoke-app (Contoso Apps, uksouth)     Connected; its peering's
                                                 remoteGateways and the gateway's
                                                 remoteVirtualNetworkPeerings name each other
        <-> vnet-spoke-data (Contoso Apps, westeurope) Disconnected; vm-data in
                                                 snet-data, which has no route table
        <-> vnet-partner                           a network you can't see
      vnet-lab (Contoso Apps, westeurope)        no peerings

    Management groups: Tenant Root Group > Platform > Contoso Connectivity,
    and Tenant Root Group > Landing zones > Contoso Apps.
#>
. (Join-Path -Path $PSScriptRoot -ChildPath 'ContosoEstate.ps1')

function Get-AACContosoTopology {
    $hub = '11111111-1111-1111-1111-111111111111'
    $app = '22222222-2222-2222-2222-222222222222'
    $net = { param($Sub, $Group, $Type, $Name) "/subscriptions/$Sub/resourceGroups/$Group/providers/Microsoft.Network/$Type/$Name" }
    $hubVnet = & $net $hub 'rg-hub' 'virtualNetworks' 'vnet-hub'
    $appVnet = & $net $app 'rg-spoke-app' 'virtualNetworks' 'vnet-spoke-app'
    $dataVnet = & $net $app 'rg-spoke-data' 'virtualNetworks' 'vnet-spoke-data'
    $partner = '/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-partner/providers/Microsoft.Network/virtualNetworks/vnet-partner'
    $gateway = & $net $hub 'rg-hub' 'virtualNetworkGateways' 'vgw-hub'
    $peering = {
        param([string] $Remote, [string] $State, [bool] $Transit, [bool] $RemoteGateway)
        $p = [ordered]@{ remoteVirtualNetwork = @{ id = $Remote }; allowForwardedTraffic = $true; peeringState = $State }
        if ($Transit) { $p.allowGatewayTransit = $true }
        if ($RemoteGateway) { $p.useRemoteGateways = $true }
        @{ name = "to-$(($Remote -split '/')[-1])"; properties = $p }
    }
    $subnet = { param($Vnet, $Name, $Prefix) @{ id = "$Vnet/subnets/$Name"; name = $Name; properties = @{ addressPrefix = $Prefix } } }
    $row = {
        param($Sub, $Group, $Type, $Name, $Location, $Properties)
        @{ id = "/subscriptions/$Sub/resourceGroups/$Group/providers/$Type/$Name"; name = $Name; type = $Type; kind = ''; location = $Location; resourceGroup = $Group; subscriptionId = $Sub; sku = $null; tags = @{}; properties = $Properties }
    }
    $vm = {
        param($Sub, $Group, $Name, $Location, $SubnetId, $Ip, [bool] $Forwarding)
        $nicId = "/subscriptions/$Sub/resourceGroups/$Group/providers/Microsoft.Network/networkInterfaces/nic-$Name"
        & $row $Sub $Group 'Microsoft.Compute/virtualMachines' $Name $Location @{ hardwareProfile = @{ vmSize = 'Standard_D2s_v5' }; networkProfile = @{ networkInterfaces = @(@{ id = $nicId }) }; storageProfile = @{ osDisk = @{ osType = 'Linux' } } }
        & $row $Sub $Group 'Microsoft.Network/networkInterfaces' "nic-$Name" $Location @{
            virtualMachine = @{ id = "/subscriptions/$Sub/resourceGroups/$Group/providers/Microsoft.Compute/virtualMachines/$Name" }; enableIPForwarding = $Forwarding
            ipConfigurations = @(@{ id = "$nicId/ipConfigurations/ipconfig1"; properties = @{ privateIPAddress = $Ip; subnet = @{ id = $SubnetId } } })
        }
    }

    # The estate, copied so it can be changed here.
    $rows = foreach ($r in @(Get-AACContosoEstate)) { ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $r -Depth 30) -AsHashtable }
    foreach ($r in $rows) {
        switch ($r.name) {
            'vnet-hub' {
                $r.properties.subnets = @($r.properties.subnets) + (& $subnet $hubVnet 'snet-nva' '10.0.4.0/28')
                $r.properties.virtualNetworkPeerings = @($r.properties.virtualNetworkPeerings) + (& $peering $dataVnet 'Disconnected' $true $false) + (& $peering $partner 'Connected' $false $false)
            }
            'vnet-spoke-app' { foreach ($p in $r.properties.virtualNetworkPeerings) { $p.properties.remoteGateways = @(@{ id = $gateway }) } }
            'vgw-hub' { $r.properties.remoteVirtualNetworkPeerings = @(@{ id = "$appVnet/virtualNetworkPeerings/to-vnet-hub" }) }
        }
    }
    $rows
    & $row $app 'rg-spoke-data' 'Microsoft.Network/virtualNetworks' 'vnet-spoke-data' 'westeurope' @{
        addressSpace = @{ addressPrefixes = @('10.2.0.0/16') }
        subnets = @(& $subnet $dataVnet 'snet-data' '10.2.1.0/24')
        virtualNetworkPeerings = @(& $peering $hubVnet 'Disconnected' $false $true)
    }
    & $vm $app 'rg-spoke-data' 'vm-data' 'westeurope' "$dataVnet/subnets/snet-data" '10.2.1.4' $false
    $labVnet = & $net $app 'rg-lab' 'virtualNetworks' 'vnet-lab'
    & $row $app 'rg-lab' 'Microsoft.Network/virtualNetworks' 'vnet-lab' 'westeurope' @{ addressSpace = @{ addressPrefixes = @('10.9.0.0/16') }; subnets = @(& $subnet $labVnet 'snet-lab' '10.9.1.0/24'); virtualNetworkPeerings = @() }
    & $vm $hub 'rg-hub' 'vm-nva' 'uksouth' "$hubVnet/subnets/snet-nva" '10.0.4.4' $true
}

function Get-AACContosoTopologySubscription {
    $root = @{ name = '00000000-0000-0000-0000-0000000000aa'; displayName = 'Tenant Root Group' }
    @(
        @{ subscriptionId = '11111111-1111-1111-1111-111111111111'; name = 'Contoso Connectivity'; chain = @(@{ name = 'mg-platform'; displayName = 'Platform' }, $root) }
        @{ subscriptionId = '22222222-2222-2222-2222-222222222222'; name = 'Contoso Apps'; chain = @(@{ name = 'mg-landingzones'; displayName = 'Landing zones' }, $root) }
    )
}
