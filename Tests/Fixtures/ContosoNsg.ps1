<#
    Made-up Contoso network security groups as Azure Resource Graph returns
    them (hashtables), with the NICs, subnets, flow logs and diagnostic
    settings Get-AACNetworkSecurityGroup reads - for NetworkSecurityGroup.Tests.ps1.

      nsg-web     on vnet-spoke/snet-web: HTTPS from the internet (to asg-web),
                  SSH from anywhere (High), 8000-9000 from the internet
                  (Medium), everything from the VNet (Low), a duplicate HTTPS
                  rule (shadowed); VNet flow log (30 days) with Traffic
                  Analytics; diagnostics to Log Analytics
      nsg-mgmt    on NIC nic-web-02 (vm-web-02, in snet-web, in asg-web): RDP
                  from 0.0.0.0/0 (High) - and it conflicts with nsg-web; no
                  diagnostic settings
      nsg-data    on vnet-data/snet-data: SQL from the app subnet, deny the
                  internet; no flow log (Medium)
      nsg-legacy  on vnet-legacy/snet-legacy: only an NSG flow log (retiring),
                  without Traffic Analytics
      nsg-unused  on nothing
#>
function Get-AACContosoNsg {
    $sub = '22222222-2222-2222-2222-222222222222'
    $rg = "/subscriptions/$sub/resourceGroups"
    $nsgId = { param($Name) "$rg/rg-network/providers/Microsoft.Network/networkSecurityGroups/$Name" }
    $vnetId = { param($Name) "$rg/rg-network/providers/Microsoft.Network/virtualNetworks/$Name" }
    $subnetId = { param($Vnet, $Name) "$(& $vnetId $Vnet)/subnets/$Name" }
    $nicId = { param($Name) "$rg/rg-app/providers/Microsoft.Network/networkInterfaces/$Name" }
    $asgId = "$rg/rg-app/providers/Microsoft.Network/applicationSecurityGroups/asg-web"
    $rule = {
        param([string] $Name, [int] $Priority, [string] $Direction, [string] $Access, [string] $Protocol, [string] $Source, [string] $Ports, [hashtable] $Extra = @{})
        $p = @{ priority = $Priority; direction = $Direction; access = $Access; protocol = $Protocol; sourceAddressPrefix = $Source; sourcePortRange = '*'; destinationAddressPrefix = '*'; destinationPortRange = $Ports }
        foreach ($k in $Extra.Keys) { $p[$k] = $Extra[$k] }
        @{ name = $Name; properties = $p }
    }
    $defaults = @(
        & $rule 'AllowVnetInBound' 65000 'Inbound' 'Allow' '*' 'VirtualNetwork' '*' @{ destinationAddressPrefix = 'VirtualNetwork' }
        & $rule 'AllowAzureLoadBalancerInBound' 65001 'Inbound' 'Allow' '*' 'AzureLoadBalancer' '*'
        & $rule 'DenyAllInBound' 65500 'Inbound' 'Deny' '*' '*' '*'
        & $rule 'AllowVnetOutBound' 65000 'Outbound' 'Allow' '*' 'VirtualNetwork' '*' @{ destinationAddressPrefix = 'VirtualNetwork' }
        & $rule 'AllowInternetOutBound' 65001 'Outbound' 'Allow' '*' '*' '*' @{ destinationAddressPrefix = 'Internet' }
        & $rule 'DenyAllOutBound' 65500 'Outbound' 'Deny' '*' '*' '*'
    )
    $nsg = {
        param([string] $Name, [object[]] $Rules, [string[]] $Subnets = @(), [string[]] $Nics = @())
        @{
            id = (& $nsgId $Name); name = $Name; resourceGroup = 'rg-network'; subscriptionId = $sub; location = 'uksouth'; tags = @{ owner = 'network' }
            properties = @{
                securityRules = @($Rules); defaultSecurityRules = $defaults
                subnets = @($Subnets | ForEach-Object { @{ id = $_ } }); networkInterfaces = @($Nics | ForEach-Object { @{ id = $_ } })
            }
        }
    }
    @{
        SubscriptionId        = $sub
        NetworkSecurityGroups = @(
            & $nsg 'nsg-web' @(
                & $rule 'Allow-HTTPS-In' 100 'Inbound' 'Allow' 'Tcp' 'Internet' '443' @{ destinationAddressPrefix = ''; destinationApplicationSecurityGroups = @(@{ id = $asgId }) }
                & $rule 'Allow-SSH-Anywhere' 110 'Inbound' 'Allow' 'Tcp' '*' '22'
                & $rule 'Allow-App-Range' 120 'Inbound' 'Allow' 'Tcp' 'Internet' '8000-9000'
                & $rule 'Allow-VNet-All' 130 'Inbound' 'Allow' '*' 'VirtualNetwork' '*'
                & $rule 'Allow-HTTPS-Again' 400 'Inbound' 'Allow' 'Tcp' 'Internet' '443' @{ destinationAddressPrefix = ''; destinationApplicationSecurityGroups = @(@{ id = $asgId }) }
                & $rule 'Deny-SMTP-Out' 200 'Outbound' 'Deny' 'Tcp' '*' '25'
            ) @((& $subnetId 'vnet-spoke' 'snet-web'))
            & $nsg 'nsg-mgmt' @(& $rule 'Allow-RDP' 100 'Inbound' 'Allow' 'Tcp' '0.0.0.0/0' '3389') @() @((& $nicId 'nic-web-02'))
            & $nsg 'nsg-data' @(
                & $rule 'Allow-Sql-From-App' 100 'Inbound' 'Allow' 'Tcp' '10.1.1.0/24' '1433'
                & $rule 'Deny-Internet' 200 'Inbound' 'Deny' '*' 'Internet' '*'
            ) @((& $subnetId 'vnet-data' 'snet-data'))
            & $nsg 'nsg-legacy' @(& $rule 'Allow-HTTP' 100 'Inbound' 'Allow' 'Tcp' 'Internet' '80') @((& $subnetId 'vnet-legacy' 'snet-legacy'))
            & $nsg 'nsg-unused' @(& $rule 'Allow-Anything' 100 'Inbound' 'Allow' '*' 'Internet' '*')
        )
        NetworkInterfaces     = @(
            @{ id = (& $nicId 'nic-web-01'); name = 'nic-web-01'; resourceGroup = 'rg-app'; nsg = ''; vm = "$rg/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-01"; subnet = (& $subnetId 'vnet-spoke' 'snet-web'); ips = @('10.1.1.4'); asgs = @($asgId) }
            @{ id = (& $nicId 'nic-web-02'); name = 'nic-web-02'; resourceGroup = 'rg-app'; nsg = (& $nsgId 'nsg-mgmt'); vm = "$rg/rg-app/providers/Microsoft.Compute/virtualMachines/vm-web-02"; subnet = (& $subnetId 'vnet-spoke' 'snet-web'); ips = @('10.1.1.5'); asgs = @($asgId) }
        )
        Subnets               = @(
            @{ subnetId = (& $subnetId 'vnet-spoke' 'snet-web'); name = 'snet-web'; vnetId = (& $vnetId 'vnet-spoke'); vnetName = 'vnet-spoke'; prefix = '10.1.1.0/24'; nsg = (& $nsgId 'nsg-web') }
            @{ subnetId = (& $subnetId 'vnet-data' 'snet-data'); name = 'snet-data'; vnetId = (& $vnetId 'vnet-data'); vnetName = 'vnet-data'; prefix = '10.2.1.0/24'; nsg = (& $nsgId 'nsg-data') }
            @{ subnetId = (& $subnetId 'vnet-legacy' 'snet-legacy'); name = 'snet-legacy'; vnetId = (& $vnetId 'vnet-legacy'); vnetName = 'vnet-legacy'; prefix = '10.9.0.0/24'; nsg = (& $nsgId 'nsg-legacy') }
        )
        FlowLogs              = @(
            @{ id = '/x/flowLogs/fl-vnet-spoke'; name = 'fl-vnet-spoke'; target = (& $vnetId 'vnet-spoke'); enabled = $true; retentionEnabled = $true; retentionDays = 30; storageId = '/x/storageAccounts/stflowlogs'; analytics = $true; workspace = '/x/workspaces/law-network'; interval = 10; version = 2 }
            @{ id = '/x/flowLogs/fl-nsg-legacy'; name = 'fl-nsg-legacy'; target = (& $nsgId 'nsg-legacy'); enabled = $true; retentionEnabled = $false; retentionDays = 0; storageId = '/x/storageAccounts/stflowlogs'; analytics = $false; workspace = ''; interval = 60; version = 2 }
        )
        Diagnostics           = @{
            (& $nsgId 'nsg-web').ToLowerInvariant()    = @{ Status = 'Enabled'; Settings = @([pscustomobject]@{ Name = 'to-law'; Workspace = 'law-security'; Storage = ''; EventHub = ''; Categories = 'allLogs' }) }
            (& $nsgId 'nsg-mgmt').ToLowerInvariant()   = @{ Status = 'Disabled'; Settings = @() }
            (& $nsgId 'nsg-data').ToLowerInvariant()   = @{ Status = 'Enabled'; Settings = @([pscustomobject]@{ Name = 'to-storage'; Workspace = ''; Storage = 'staudit'; EventHub = ''; Categories = 'NetworkSecurityGroupEvent' }) }
            (& $nsgId 'nsg-legacy').ToLowerInvariant() = @{ Status = 'Disabled'; Settings = @() }
            (& $nsgId 'nsg-unused').ToLowerInvariant() = @{ Status = 'Disabled'; Settings = @() }
        }
    }
}
