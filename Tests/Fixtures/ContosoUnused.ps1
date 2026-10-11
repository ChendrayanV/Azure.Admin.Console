<#
    A made-up Contoso estate for UnusedResource.Tests.ps1, as Azure Resource
    Graph returns it (Get-AACUnusedResourceQuery's queries):

      disk-premium   Premium, 1024 GiB, unattached 40 days     -> Medium
      disk-std       Standard, 32 GiB                          -> Low
      nic-old        attached to nothing                       -> Low
      pip-std        Standard public IP                        -> Medium
      pip-basic      Basic, dynamic                            -> Low (not billed)
      lb-empty       Standard, its pool empty                  -> Medium
      lb-busy        a backend in its pool                     -> nothing
      agw-empty      every pool empty                          -> High
      plan-p1        Premium v3 plan, no apps                  -> High
      plan-free      Free plan, no apps                        -> Low
      vm-stopped     stopped, not deallocated                  -> High
      vm-dealloc     deallocated                               -> Low (partly billed)
      snap-old       200 days old                              -> Low
      snap-new       10 days old                               -> nothing
      ddos-plan      protecting nothing                        -> High
      pool-empty     SQL elastic pool, no databases            -> High
      pool-busy      two databases                             -> nothing
      rg-empty       no resources                              -> Low
      rg-app         resources in it                           -> nothing
      rg-managed     empty, but managed by an application      -> nothing
      disk-other     in a subscription not in scope            -> left out
#>
function Get-AACContosoUnused {
    $sub = '11111111-1111-1111-1111-111111111111'
    $other = '99999999-9999-9999-9999-999999999999'
    $now = [datetime]::UtcNow
    $ago = { param([int] $Days) $now.AddDays(-$Days).ToString('o', [cultureinfo]::InvariantCulture) }
    $row = {
        param([string] $Type, [string] $Name, [hashtable] $Extra = @{}, [string] $Group = 'rg-app', [string] $Sub = $sub)
        $r = @{ id = "/subscriptions/$Sub/resourcegroups/$Group/providers/$Type/$Name".ToLowerInvariant(); name = $Name; type = $Type; resourceGroup = $Group; subscriptionId = $Sub; location = 'westeurope' }
        foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
        $r
    }
    $pool = { param([int] $Backends) @{ name = 'pool'; properties = @{ backendIPConfigurations = @(1..$Backends | Where-Object { $Backends } | ForEach-Object { @{ id = "ipconfig$_" } }) } } }

    @{
        Subscription = $sub
        Names        = @{ $sub = 'sub-prod' }
        Read         = @{
            Errors = @{}
            Rows   = @{
                disks            = @(
                    (& $row 'microsoft.compute/disks' 'disk-premium' @{ sku = 'Premium_LRS'; sizeGb = 1024; created = (& $ago 400); detached = (& $ago 40) })
                    (& $row 'microsoft.compute/disks' 'disk-std' @{ sku = 'Standard_LRS'; sizeGb = 32; created = (& $ago 5); detached = $null })
                    (& $row 'microsoft.compute/disks' 'disk-other' @{ sku = 'Premium_LRS'; sizeGb = 64 } 'rg-x' $other)
                )
                nics             = @((& $row 'microsoft.network/networkinterfaces' 'nic-old'))
                publicIps        = @((& $row 'microsoft.network/publicipaddresses' 'pip-std' @{ sku = 'Standard'; allocation = 'Static'; ip = '20.1.2.3' }), (& $row 'microsoft.network/publicipaddresses' 'pip-basic' @{ sku = 'Basic'; allocation = 'Dynamic'; ip = '' }))
                nsgs             = @()
                routeTables      = @()
                natGateways      = @()
                loadBalancers    = @((& $row 'microsoft.network/loadbalancers' 'lb-empty' @{ sku = 'Standard'; pools = @((& $pool 0)); rules = 1 }), (& $row 'microsoft.network/loadbalancers' 'lb-busy' @{ sku = 'Standard'; pools = @((& $pool 2)); rules = 1 }))
                appGateways      = @((& $row 'microsoft.network/applicationgateways' 'agw-empty' @{ sku = 'Standard_v2'; state = 'Running'; pools = @(@{ name = 'p'; properties = @{ backendAddresses = @() } }) }))
                plans            = @((& $row 'microsoft.web/serverfarms' 'plan-p1' @{ sku = 'P1v3'; tier = 'PremiumV3'; workers = 2 }), (& $row 'microsoft.web/serverfarms' 'plan-free' @{ sku = 'F1'; tier = 'Free'; workers = 0 }))
                availabilitySets = @()
                vms              = @((& $row 'microsoft.compute/virtualmachines' 'vm-stopped' @{ size = 'Standard_D4s_v5'; power = 'PowerState/stopped' }), (& $row 'microsoft.compute/virtualmachines' 'vm-dealloc' @{ size = 'Standard_B2s'; power = 'PowerState/deallocated' }))
                snapshots        = @((& $row 'microsoft.compute/snapshots' 'snap-old' @{ sku = 'Standard_LRS'; sizeGb = 128; created = (& $ago 200); incremental = $true }), (& $row 'microsoft.compute/snapshots' 'snap-new' @{ sku = 'Standard_LRS'; sizeGb = 128; created = (& $ago 10) }))
                dnsZones         = @()
                trafficManager   = @()
                ipGroups         = @()
                ddosPlans        = @((& $row 'microsoft.network/ddosprotectionplans' 'ddos-plan' @{} 'rg-net'))
                wafPolicies      = @()
                certificates     = @()
                elasticPools     = @((& $row 'microsoft.sql/servers/elasticpools' 'pool-empty' @{ sku = 'StandardPool'; tier = 'Standard' } 'rg-data'), (& $row 'microsoft.sql/servers/elasticpools' 'pool-busy' @{ sku = 'StandardPool'; tier = 'Standard' } 'rg-data'))
                pooledDatabases  = @(@{ pool = "/subscriptions/$sub/resourcegroups/rg-data/providers/microsoft.sql/servers/elasticpools/pool-busy"; databases = 2 })
                groups           = @(
                    @{ id = "/subscriptions/$sub/resourcegroups/rg-empty"; name = 'rg-empty'; resourceGroup = 'rg-empty'; subscriptionId = $sub; location = 'westeurope'; managedBy = '' }
                    @{ id = "/subscriptions/$sub/resourcegroups/rg-app"; name = 'rg-app'; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope'; managedBy = '' }
                    @{ id = "/subscriptions/$sub/resourcegroups/rg-managed"; name = 'rg-managed'; resourceGroup = 'rg-managed'; subscriptionId = $sub; location = 'westeurope'; managedBy = '/subscriptions/x/providers/microsoft.solutions/applications/app' }
                )
                groupCounts      = @(@{ subscriptionId = $sub; resourceGroup = 'rg-app'; resources = 12 }, @{ subscriptionId = $sub; resourceGroup = 'rg-net'; resources = 1 }, @{ subscriptionId = $sub; resourceGroup = 'rg-data'; resources = 3 })
            }
        }
    }
}
