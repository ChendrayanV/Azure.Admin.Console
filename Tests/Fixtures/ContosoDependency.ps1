<#
    A made-up Contoso shop for DependencyGraph.Tests.ps1, as Resource Graph
    (Get-AACDependencyQuery) and Application Insights return it:

      fd-shop (Front Door) -> app-shop                     (its only origin)
      agw-shop (1 instance) -> vm-api (by IP), app-shop    (vm-api alone in its pool)
      lb-web -> vm-web-1, vm-web-2                          (two in the pool)
      app-shop, app-api -> plan-shop (1 instance)
      app-shop's identity -> stshop (LRS), sqldb-orders (no zone redundancy)
      sqldb-orders -> sqlsrv; pe-sql -> sqlsrv
      VMs, app-shop (integration), pe-sql -> vnet-spoke; vnet-spoke <-> vnet-hub (peered)
      telemetry: app-shop calls sqlsrv, api.stripe.com and app-api; app-api calls app-shop (a cycle)
#>
function Get-AACContosoDependency {
    $sub = '11111111-1111-1111-1111-111111111111'
    $res = { param([string] $Type, [string] $Name, [string] $Group = 'rg-shop') "/subscriptions/$sub/resourcegroups/$Group/providers/$Type/$Name" }
    $spoke = & $res 'microsoft.network/virtualnetworks' 'vnet-spoke'
    $hub = & $res 'microsoft.network/virtualnetworks' 'vnet-hub' 'rg-net'
    $nic = { param([string] $Vm, [string] $Ip) @{ id = (& $res 'microsoft.network/networkinterfaces' "$Vm-nic"); vm = (& $res 'microsoft.compute/virtualmachines' $Vm); ipConfigs = @(@{ id = "$(& $res 'microsoft.network/networkinterfaces' "$Vm-nic")/ipconfigurations/ipconfig1"; properties = @{ subnet = @{ id = "$spoke/subnets/snet-app" }; privateIPAddress = $Ip } }) } }
    $vm = { param([string] $Name) @{ id = (& $res 'microsoft.compute/virtualmachines' $Name); name = $Name; type = 'microsoft.compute/virtualmachines'; resourceGroup = 'rg-shop'; subscriptionId = $sub; zones = @(); avset = ''; osDisk = (& $res 'microsoft.compute/disks' "$Name-os"); dataDisks = @(); identity = $null } }
    $web = { param([string] $Name, $Identity, [string] $Subnet) @{ id = (& $res 'microsoft.web/sites' $Name); name = $Name; type = 'microsoft.web/sites'; kind = 'app'; resourceGroup = 'rg-shop'; subscriptionId = $sub; plan = (& $res 'microsoft.web/serverfarms' 'plan-shop'); subnet = $Subnet; hosts = @("$Name.azurewebsites.net"); identity = $Identity } }
    $data = { param([string] $Type, [string] $Name, [hashtable] $More) $row = @{ id = (& $res $Type $Name); name = $Name; type = $Type; resourceGroup = 'rg-shop'; subscriptionId = $sub; zones = @(); sku = ''; tier = ''; zoneRedundant = $null; host = ''; locations = @(); ha = '' }; foreach ($k in $More.Keys) { $row[$k] = $More[$k] }; $row }
    $sqlsrv = & $res 'microsoft.sql/servers' 'sqlsrv'
    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                vms        = @((& $vm 'vm-web-1'), (& $vm 'vm-web-2'), (& $vm 'vm-api'), (& $vm 'vm-batch'))
                nics       = @((& $nic 'vm-web-1' '10.0.1.4'), (& $nic 'vm-web-2' '10.0.1.5'), (& $nic 'vm-api' '10.0.1.10'), (& $nic 'vm-batch' '10.0.1.20'))
                vnets      = @(@{ id = $spoke; name = 'vnet-spoke'; type = 'microsoft.network/virtualnetworks'; resourceGroup = 'rg-shop'; subscriptionId = $sub; peerings = @(@{ properties = @{ remoteVirtualNetwork = @{ id = $hub } } }) }, @{ id = $hub; name = 'vnet-hub'; type = 'microsoft.network/virtualnetworks'; resourceGroup = 'rg-net'; subscriptionId = $sub; peerings = @(@{ properties = @{ remoteVirtualNetwork = @{ id = $spoke } } }) })
                balancers  = @(
                    @{ id = (& $res 'microsoft.network/loadbalancers' 'lb-web'); name = 'lb-web'; type = 'microsoft.network/loadbalancers'; resourceGroup = 'rg-shop'; subscriptionId = $sub; zones = @(); capacity = $null; autoscale = $null; pools = @(@{ name = 'web'; properties = @{ backendIPConfigurations = @(@{ id = "$(& $res 'microsoft.network/networkinterfaces' 'vm-web-1-nic')/ipconfigurations/ipconfig1" }, @{ id = "$(& $res 'microsoft.network/networkinterfaces' 'vm-web-2-nic')/ipconfigurations/ipconfig1" }) } }) }
                    @{ id = (& $res 'microsoft.network/applicationgateways' 'agw-shop'); name = 'agw-shop'; type = 'microsoft.network/applicationgateways'; resourceGroup = 'rg-shop'; subscriptionId = $sub; zones = @(); capacity = 1; autoscale = $null; pools = @(@{ name = 'api'; properties = @{ backendAddresses = @(@{ ipAddress = '10.0.1.10' }) } }, @{ name = 'shop'; properties = @{ backendAddresses = @(@{ fqdn = 'app-shop.azurewebsites.net' }, @{ fqdn = 'legacy.contoso.example' }) } }) }
                )
                origins    = @(@{ id = "$(& $res 'microsoft.cdn/profiles' 'fd-shop')/origingroups/og/origins/o1"; profile = (& $res 'microsoft.cdn/profiles' 'fd-shop'); host = 'app-shop.azurewebsites.net' })
                profiles   = @(@{ id = (& $res 'microsoft.cdn/profiles' 'fd-shop'); name = 'fd-shop'; type = 'microsoft.cdn/profiles'; resourceGroup = 'rg-shop'; subscriptionId = $sub })
                web        = @((& $web 'app-shop' @{ principalId = 'p-shop' } "$spoke/subnets/snet-int"), (& $web 'app-api' $null ''))
                plans      = @(@{ id = (& $res 'microsoft.web/serverfarms' 'plan-shop'); name = 'plan-shop'; type = 'microsoft.web/serverfarms'; resourceGroup = 'rg-shop'; subscriptionId = $sub; capacity = 1; tier = 'PremiumV3'; zoneRedundant = $false })
                endpoints  = @(@{ id = (& $res 'microsoft.network/privateendpoints' 'pe-sql'); name = 'pe-sql'; type = 'microsoft.network/privateendpoints'; resourceGroup = 'rg-shop'; subscriptionId = $sub; subnet = "$spoke/subnets/snet-pe"; links = @(@{ properties = @{ privateLinkServiceId = $sqlsrv } }) })
                clusters   = @()
                data       = @(
                    (& $data 'microsoft.storage/storageaccounts' 'stshop' @{ sku = 'Standard_LRS'; host = 'stshop.blob.core.windows.net' })
                    (& $data 'microsoft.sql/servers' 'sqlsrv' @{ host = 'sqlsrv.database.windows.net' })
                    @{ id = "$sqlsrv/databases/sqldb-orders"; name = 'sqldb-orders'; type = 'microsoft.sql/servers/databases'; resourceGroup = 'rg-shop'; subscriptionId = $sub; zones = @(); sku = 'GP_Gen5_2'; tier = 'GeneralPurpose'; zoneRedundant = $false; host = ''; locations = @(); ha = '' }
                    (& $data 'microsoft.keyvault/vaults' 'kv-shop' @{ host = 'kv-shop.vault.azure.net' })
                )
                identities = @()
                roles      = @(
                    @{ id = 'ra1'; principalId = 'p-shop'; scope = "$(& $res 'microsoft.storage/storageaccounts' 'stshop')/blobservices/default/containers/images"; roleId = 'x' }
                    @{ id = 'ra2'; principalId = 'p-shop'; scope = "$sqlsrv/databases/sqldb-orders"; roleId = 'x' }
                    @{ id = 'ra3'; principalId = 'p-other'; scope = (& $res 'microsoft.keyvault/vaults' 'kv-shop'); roleId = 'x' }
                )
                insights   = @(@{ id = 'ai1'; name = 'ai-shop'; workspace = '/subscriptions/s/resourcegroups/rg/providers/microsoft.operationalinsights/workspaces/law-shop' })
                workspaces = @(@{ id = '/subscriptions/s/resourcegroups/rg/providers/microsoft.operationalinsights/workspaces/law-shop'; customerId = 'ws-guid' })
            }
        }
        Telemetry    = @(
            @{ AppRoleName = 'app-shop'; Target = 'sqlsrv.database.windows.net | orders'; DependencyType = 'SQL'; Calls = 5000; Failed = 50 }
            @{ AppRoleName = 'app-shop'; Target = 'api.stripe.com'; DependencyType = 'HTTP'; Calls = 300; Failed = 0 }
            @{ AppRoleName = 'app-shop'; Target = 'app-api.azurewebsites.net'; DependencyType = 'HTTP'; Calls = 900; Failed = 9 }
            @{ AppRoleName = 'app-api'; Target = 'app-shop.azurewebsites.net:443'; DependencyType = 'HTTP'; Calls = 200; Failed = 2 }
        )
    }
}
