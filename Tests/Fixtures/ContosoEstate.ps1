<#
    A made-up Contoso hub-and-spoke estate as Azure Resource Graph returns it
    (hashtables, as Invoke-AACArmRequest gives them): the rows the resource
    map is built from in ResourceMap.Tests.ps1.

      Contoso Connectivity / rg-hub    vnet-hub: firewall (10.0.1.4), Bastion,
                                       VPN gateway; firewall policy; private
                                       DNS zone linked to vnet-hub
      Contoso Apps / rg-spoke-app      vnet-spoke-app (peered with vnet-hub):
                                       snet-web (nsg-web, rt-spoke: 0.0.0.0/0
                                       -> 10.0.1.4, and 192.168.0.0/16 to an
                                       appliance IP nothing has), snet-pe; two
                                       VMs with NICs (nic-web-02 with its own
                                       NSG, open to RDP from anywhere)
                                       and disks; an app on its plan with VNet
                                       integration; SQL with a private
                                       endpoint; Key Vault, storage, Log
                                       Analytics and Application Insights; an
                                       unattached disk and NIC
#>
function Get-AACContosoEstate {
    $hubSub = '11111111-1111-1111-1111-111111111111'
    $appSub = '22222222-2222-2222-2222-222222222222'
    $hub = "/subscriptions/$hubSub/resourceGroups/rg-hub/providers"
    $app = "/subscriptions/$appSub/resourceGroups/rg-spoke-app/providers"
    $row = {
        param([string] $Id, [string] $Type, [hashtable] $Properties, [hashtable] $Extra = @{})
        $parts = $Id -split '/'
        $r = @{ id = $Id; name = $parts[-1]; type = $Type; kind = ''; location = 'uksouth'; resourceGroup = $parts[4]; subscriptionId = $parts[2]; sku = $null; properties = $Properties; tags = @{ env = 'prod' } }
        foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
        $r
    }
    $ref = { param([string] $Id) @{ id = $Id } }
    $hubVnet = "$hub/Microsoft.Network/virtualNetworks/vnet-hub"
    $spokeVnet = "$app/Microsoft.Network/virtualNetworks/vnet-spoke-app"
    $snet = { param([string] $Vnet, [string] $Name) "$Vnet/subnets/$Name" }

    @(
        # --- The hub -------------------------------------------------------------------------------
        & $row $hubVnet 'Microsoft.Network/virtualNetworks' @{
            addressSpace           = @{ addressPrefixes = @('10.0.0.0/16') }
            subnets                = @(
                @{ id = (& $snet $hubVnet 'AzureFirewallSubnet'); name = 'AzureFirewallSubnet'; properties = @{ addressPrefix = '10.0.1.0/26'; ipConfigurations = @(& $ref "$hub/Microsoft.Network/azureFirewalls/afw-hub/azureFirewallIpConfigurations/ipconfig") } }
                @{ id = (& $snet $hubVnet 'AzureBastionSubnet'); name = 'AzureBastionSubnet'; properties = @{ addressPrefix = '10.0.2.0/26' } }
                @{ id = (& $snet $hubVnet 'GatewaySubnet'); name = 'GatewaySubnet'; properties = @{ addressPrefix = '10.0.3.0/27' } }
            )
            virtualNetworkPeerings = @(@{ id = "$hubVnet/virtualNetworkPeerings/hub-to-app"; properties = @{ peeringState = 'Connected'; remoteVirtualNetwork = (& $ref $spokeVnet); allowGatewayTransit = $true; allowForwardedTraffic = $true } })
        }
        & $row "$hub/Microsoft.Network/azureFirewalls/afw-hub" 'Microsoft.Network/azureFirewalls' @{
            sku              = @{ tier = 'Premium' }
            firewallPolicy   = & $ref "$hub/Microsoft.Network/firewallPolicies/afwp-hub"
            ipConfigurations = @(@{ id = "$hub/Microsoft.Network/azureFirewalls/afw-hub/azureFirewallIpConfigurations/ipconfig"; properties = @{ privateIPAddress = '10.0.1.4'; subnet = (& $ref (& $snet $hubVnet 'AzureFirewallSubnet')); publicIPAddress = (& $ref "$hub/Microsoft.Network/publicIPAddresses/pip-afw") } })
        }
        & $row "$hub/Microsoft.Network/firewallPolicies/afwp-hub" 'Microsoft.Network/firewallPolicies' @{ firewalls = @(& $ref "$hub/Microsoft.Network/azureFirewalls/afw-hub") }
        & $row "$hub/Microsoft.Network/publicIPAddresses/pip-afw" 'Microsoft.Network/publicIPAddresses' @{ ipAddress = '20.50.10.4'; ipConfiguration = (& $ref "$hub/Microsoft.Network/azureFirewalls/afw-hub/azureFirewallIpConfigurations/ipconfig") } @{ sku = @{ name = 'Standard' } }
        & $row "$hub/Microsoft.Network/bastionHosts/bas-hub" 'Microsoft.Network/bastionHosts' @{
            ipConfigurations = @(@{ properties = @{ subnet = (& $ref (& $snet $hubVnet 'AzureBastionSubnet')); publicIPAddress = (& $ref "$hub/Microsoft.Network/publicIPAddresses/pip-bas") } })
        }
        & $row "$hub/Microsoft.Network/publicIPAddresses/pip-bas" 'Microsoft.Network/publicIPAddresses' @{ ipAddress = '20.50.10.5'; ipConfiguration = (& $ref "$hub/Microsoft.Network/bastionHosts/bas-hub/bastionHostIpConfigurations/ipconf") }
        & $row "$hub/Microsoft.Network/virtualNetworkGateways/vgw-hub" 'Microsoft.Network/virtualNetworkGateways' @{
            ipConfigurations = @(@{ properties = @{ subnet = (& $ref (& $snet $hubVnet 'GatewaySubnet')) } })
        }
        & $row "$hub/Microsoft.Network/privateDnsZones/privatelink.database.windows.net" 'Microsoft.Network/privateDnsZones' @{ numberOfRecordSets = 2 }
        & $row "$hub/Microsoft.Network/privateDnsZones/privatelink.database.windows.net/virtualNetworkLinks/link-hub" 'Microsoft.Network/privateDnsZones/virtualNetworkLinks' @{ virtualNetwork = (& $ref $hubVnet); registrationEnabled = $false }

        # --- The spoke -----------------------------------------------------------------------------
        & $row $spokeVnet 'Microsoft.Network/virtualNetworks' @{
            addressSpace           = @{ addressPrefixes = @('10.1.0.0/16') }
            subnets                = @(
                @{ id = (& $snet $spokeVnet 'snet-web'); name = 'snet-web'; properties = @{
                        addressPrefix = '10.1.1.0/24'; networkSecurityGroup = (& $ref "$app/Microsoft.Network/networkSecurityGroups/nsg-web"); routeTable = (& $ref "$app/Microsoft.Network/routeTables/rt-spoke")
                        ipConfigurations = @(1, 2 | ForEach-Object { & $ref "$app/Microsoft.Network/networkInterfaces/nic-web-0$_/ipConfigurations/ipconfig1" }) + @(& $ref "$app/Microsoft.Network/networkInterfaces/nic-leftover/ipConfigurations/ipconfig1")
                        serviceEndpoints = @(@{ service = 'Microsoft.Storage' })
                    }
                }
                @{ id = (& $snet $spokeVnet 'snet-pe'); name = 'snet-pe'; properties = @{ addressPrefix = '10.1.2.0/24'; privateEndpoints = @(& $ref "$app/Microsoft.Network/privateEndpoints/pe-sql") } }
                @{ id = (& $snet $spokeVnet 'snet-integration'); name = 'snet-integration'; properties = @{ addressPrefix = '10.1.3.0/26'; delegations = @(@{ name = 'web'; properties = @{ serviceName = 'Microsoft.Web/serverFarms' } }) } }
            )
            virtualNetworkPeerings = @(@{ id = "$spokeVnet/virtualNetworkPeerings/app-to-hub"; properties = @{ peeringState = 'Connected'; remoteVirtualNetwork = (& $ref $hubVnet); useRemoteGateways = $true; allowForwardedTraffic = $true } })
        }
        $rule = {
            param([string] $Name, [int] $Priority, [string] $Direction, [string] $Access, [string] $Source, [string] $Ports, [hashtable] $Extra = @{})
            $properties = @{ priority = $Priority; direction = $Direction; access = $Access; protocol = 'Tcp'; sourceAddressPrefix = $Source; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = $Ports }
            foreach ($k in $Extra.Keys) { $properties[$k] = $Extra[$k] }
            @{ name = $Name; properties = $properties }
        }
        $defaults = @(
            & $rule 'AllowVnetInBound' 65000 'Inbound' 'Allow' 'VirtualNetwork' '*'
            & $rule 'DenyAllInBound' 65500 'Inbound' 'Deny' '*' '*'
            & $rule 'AllowInternetOutBound' 65001 'Outbound' 'Allow' '*' '*'
        )
        & $row "$app/Microsoft.Network/networkSecurityGroups/nsg-web" 'Microsoft.Network/networkSecurityGroups' @{
            subnets              = @(& $ref (& $snet $spokeVnet 'snet-web'))
            securityRules        = @(
                & $rule 'Allow-HTTPS-In' 100 'Inbound' 'Allow' 'Internet' '443' @{ destinationApplicationSecurityGroups = @(& $ref "$app/Microsoft.Network/applicationSecurityGroups/asg-web") }
                & $rule 'Allow-SSH-Anywhere' 110 'Inbound' 'Allow' '*' '22'
                & $rule 'Allow-AzureLB' 120 'Inbound' 'Allow' 'AzureLoadBalancer' '*'
                & $rule 'Deny-Outbound-SMTP' 200 'Outbound' 'Deny' '*' '25'
            )
            defaultSecurityRules = $defaults
        }
        & $row "$app/Microsoft.Network/networkSecurityGroups/nsg-mgmt" 'Microsoft.Network/networkSecurityGroups' @{
            networkInterfaces    = @(& $ref "$app/Microsoft.Network/networkInterfaces/nic-web-02")
            securityRules        = @(& $rule 'Allow-RDP' 100 'Inbound' 'Allow' '0.0.0.0/0' '3389')
            defaultSecurityRules = $defaults
        }
        & $row "$app/Microsoft.Network/applicationSecurityGroups/asg-web" 'Microsoft.Network/applicationSecurityGroups' @{}
        & $row "$app/Microsoft.Network/networkSecurityGroups/nsg-unused" 'Microsoft.Network/networkSecurityGroups' @{}
        & $row "$app/Microsoft.Network/routeTables/rt-spoke" 'Microsoft.Network/routeTables' @{
            subnets = @(& $ref (& $snet $spokeVnet 'snet-web'))
            routes  = @(
                @{ name = 'default'; properties = @{ addressPrefix = '0.0.0.0/0'; nextHopType = 'VirtualAppliance'; nextHopIpAddress = '10.0.1.4' } }
                @{ name = 'to-onprem'; properties = @{ addressPrefix = '192.168.0.0/16'; nextHopType = 'VirtualAppliance'; nextHopIpAddress = '10.0.1.9' } }
            )
            disableBgpRoutePropagation = $true
        }
        foreach ($n in 1, 2) {
            $vm = "$app/Microsoft.Compute/virtualMachines/vm-web-0$n"
            $nic = "$app/Microsoft.Network/networkInterfaces/nic-web-0$n"
            & $row $vm 'Microsoft.Compute/virtualMachines' @{
                hardwareProfile = @{ vmSize = 'Standard_D4s_v5' }
                storageProfile  = @{ osDisk = @{ osType = 'Linux'; managedDisk = (& $ref "$app/Microsoft.Compute/disks/vm-web-0${n}_OsDisk") } }
                networkProfile  = @{ networkInterfaces = @(& $ref $nic) }
                diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $true } }
            }
            $pip = if ($n -eq 2) { & $ref "$app/Microsoft.Network/publicIPAddresses/pip-web-02" } else { $null }
            & $row $nic 'Microsoft.Network/networkInterfaces' @{
                virtualMachine   = & $ref $vm
                networkSecurityGroup = $(if ($n -eq 2) { & $ref "$app/Microsoft.Network/networkSecurityGroups/nsg-mgmt" } else { $null })
                ipConfigurations = @(@{ id = "$nic/ipConfigurations/ipconfig1"; properties = @{ privateIPAddress = "10.1.1.$(3 + $n)"; subnet = (& $ref (& $snet $spokeVnet 'snet-web')); publicIPAddress = $pip } })
            }
            & $row "$app/Microsoft.Compute/disks/vm-web-0${n}_OsDisk" 'Microsoft.Compute/disks' @{ diskSizeGB = 64; diskState = 'Attached' } @{ managedBy = $vm; sku = @{ name = 'Premium_LRS' } }
        }
        & $row "$app/Microsoft.Network/publicIPAddresses/pip-web-02" 'Microsoft.Network/publicIPAddresses' @{ ipAddress = '51.140.1.20'; ipConfiguration = (& $ref "$app/Microsoft.Network/networkInterfaces/nic-web-02/ipConfigurations/ipconfig1") }
        & $row "$app/Microsoft.Compute/disks/disk-old-data" 'Microsoft.Compute/disks' @{ diskSizeGB = 512; diskState = 'Unattached' } @{ sku = @{ name = 'StandardSSD_LRS' } }
        & $row "$app/Microsoft.Network/networkInterfaces/nic-leftover" 'Microsoft.Network/networkInterfaces' @{
            ipConfigurations = @(@{ properties = @{ privateIPAddress = '10.1.1.9'; subnet = (& $ref (& $snet $spokeVnet 'snet-web')) } })
        }
        & $row "$app/Microsoft.Web/serverFarms/asp-orders" 'Microsoft.Web/serverFarms' @{} @{ sku = @{ name = 'P1v3' } }
        & $row "$app/Microsoft.Web/sites/app-orders" 'Microsoft.Web/sites' @{
            serverFarmId = "$app/Microsoft.Web/serverFarms/asp-orders"; defaultHostName = 'app-orders.azurewebsites.net'
            virtualNetworkSubnetId = (& $snet $spokeVnet 'snet-integration')
        } @{ kind = 'app,linux' }
        & $row "$app/Microsoft.Sql/servers/sql-orders" 'Microsoft.Sql/servers' @{ privateEndpointConnections = @(@{ properties = @{ privateEndpoint = (& $ref "$app/Microsoft.Network/privateEndpoints/pe-sql") } }) }
        & $row "$app/Microsoft.Sql/servers/sql-orders/databases/sqldb-orders" 'Microsoft.Sql/servers/databases' @{} @{ sku = @{ name = 'GP_Gen5_2' } }
        & $row "$app/Microsoft.Network/privateEndpoints/pe-sql" 'Microsoft.Network/privateEndpoints' @{
            subnet                         = & $ref (& $snet $spokeVnet 'snet-pe')
            networkInterfaces              = @(& $ref "$app/Microsoft.Network/networkInterfaces/pe-sql.nic")
            privateLinkServiceConnections  = @(@{ properties = @{ privateLinkServiceId = "$app/Microsoft.Sql/servers/sql-orders"; groupIds = @('sqlServer') } })
            customDnsConfigs               = @(@{ fqdn = 'sql-orders.database.windows.net'; ipAddresses = @('10.1.2.4') })
        }
        & $row "$app/Microsoft.Network/networkInterfaces/pe-sql.nic" 'Microsoft.Network/networkInterfaces' @{
            privateEndpoint  = & $ref "$app/Microsoft.Network/privateEndpoints/pe-sql"
            ipConfigurations = @(@{ properties = @{ privateIPAddress = '10.1.2.4'; subnet = (& $ref (& $snet $spokeVnet 'snet-pe')) } })
        }
        & $row "$app/Microsoft.KeyVault/vaults/kv-orders" 'Microsoft.KeyVault/vaults' @{} @{ sku = @{ name = 'standard' } }
        & $row "$app/Microsoft.Storage/storageAccounts/stordersdata" 'Microsoft.Storage/storageAccounts' @{
            networkAcls = @{ virtualNetworkRules = @(@{ id = (& $snet $spokeVnet 'snet-web') }) }
        } @{ sku = @{ name = 'Standard_ZRS' }; kind = 'StorageV2' }
        & $row "$app/Microsoft.OperationalInsights/workspaces/law-orders" 'Microsoft.OperationalInsights/workspaces' @{} @{ sku = @{ name = 'PerGB2018' } }
        & $row "$app/Microsoft.Insights/components/appi-orders" 'Microsoft.Insights/components' @{ WorkspaceResourceId = "$app/Microsoft.OperationalInsights/workspaces/law-orders" } @{ kind = 'web' }
    )
}
